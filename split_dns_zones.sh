#!/usr/bin/env bash

# ==============================================================================
# Script: split_dns_zones.sh
# Description: Performs an AXFR DNS zone transfer and routes records into
#              separate zone files based on a client list. Any record not
#              matching a client goes to a generic base zone file.
# Usage: ./split_dns_zones.sh -z <zone> -s <nameserver_ip> [-c <clients_file>] [-h <header_file>]
# ==============================================================================

set -euo pipefail

# Default Configurations
CLIENTS_FILE="clients.txt"
HEADER_FILE="header.txt"
ZONE=""
NAMESERVER=""

usage() {
    echo "Usage: $0 -z <zone_name> -s <nameserver_ip> [-c <clients_file>] [-h <header_file>]"
    echo ""
    echo "Options:"
    echo "  -z  Base zone to query via AXFR (e.g., example.com)"
    echo "  -s  Name server IP address to query"
    echo "  -c  File containing target client domains, one per line (Default: clients.txt)"
    echo "  -h  Header template file to adapt for each zone (Default: header.txt)"
    exit 1
}

# Parse command-line flags
while getopts "z:s:c:h:" opt; do
    case "$opt" in
        z) ZONE="$OPTARG" ;;
        s) NAMESERVER="$OPTARG" ;;
        c) CLIENTS_FILE="$OPTARG" ;;
        h) HEADER_FILE="$OPTARG" ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [[ -z "ZONE"||-z"NAMESERVER" ]]; then
    echo "Error: Zone (-z) and Nameserver (-s) are required." >&2
    usage
fi

if [[ ! -f "$HEADER_FILE" ]]; then
    echo "Error: Header template file '$HEADER_FILE' not found." >&2
    exit 1
fi

if [[ ! -f "$CLIENTS_FILE" ]]; then
    echo "Error: Clients file '$CLIENTS_FILE' not found." >&2
    exit 1
fi

# Ensure domain formatting ends with a trailing dot
[[ "ZONE"!=*.]]&&ZONEFQDN="{ZONE}." || ZONE_FQDN="$ZONE"

GENERIC_FILE="${ZONE_FQDN}txt"

echo "[+] Preparing zone output files..."

# 1. Initialize generic base zone file with adapted header
sed "s/@/ZONEFQDN/g""HEADER_FILE" > "$GENERIC_FILE"

# 2. Initialize each client zone file with adapted header
while IFS= read -r client || [[ -n "$client" ]]; do
    client=(echo"client" | xargs)
    [ -z "$client" ] && continue
    
    # Ensure trailing dot for consistent matching
    [[ "client"!=*.]]&&clientfqdn="{client}." || client_fqdn="$client"
    
    sed "s/@/clientfqdn/g""HEADER_FILE" > "${client_fqdn}txt"
done < "$CLIENTS_FILE"

echo "[+] Fetching AXFR records from server $NAMESERVER for zone $ZONE_FQDN..."

# 3. Query AXFR and route records strictly based on column 1 ($1)
dig axfr "ZONEFQDN""@NAMESERVER" | grep -vP "(^;;|^)"|awk-vclientsfile="CLIENTS_FILE" -v generic_file="$GENERIC_FILE" '
BEGIN {
    count = 0
    while ((getline c < clients_file) > 0) {
        gsub(/^[ \t]+|[ \t]+$/, "", c)
        if (length(c) > 0) {
            # Ensure clients in AWK memory also have a trailing dot
            if (substr(c, length(c)) != ".") {
                c = c "."
            }
            count++
            clients[count] = c
        }
    }
    close(clients_file)

    # Sort clients array by length descending (longest/most specific subdomains match first)
    for (i = 1; i <= count; i++) {
        for (j = i + 1; j <= count; j++) {
            if (length(clients[i]) < length(clients[j])) {
                tmp = clients[i]
                clients[i] = clients[j]
                clients[j] = tmp
            }
        }
    }
}

{
    record_domain = $1
    matched = 0

    for (i = 1; i <= count; i++) {
        c = clients[i]
        c_suffix = "." c

        # Exact domain match OR subdomain match with strict dot boundary check
        if (record_domain == c || (length(record_domain) > length(c_suffix) && substr(record_domain, length(record_domain) - length(c_suffix) + 1) == c_suffix)) {
            print $0 >> (c "txt")
            matched = 1
            break
        }
    }

    if (!matched) {
        print $0 >> generic_file
    }
}'

echo "[+] Completed! Records successfully routed into zone files."
