# DNS AXFR Zone Splitter

A Bash script to perform an AXFR zone transfer and automatically split returned DNS records into separate zone files based on a client domain list.

## Usage

```bash
chmod +x split_dns_zones.sh
./split_dns_zones.sh -z example.com -s 192.168.1.1 -c clients.txt -h header.txt
