#!/bin/bash

set -euo pipefail

# Variables
domain=""
file=""
skip_subfinder=false

# Arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d)
      domain="$2"
      shift 2
      ;;
    -f)
      file="$2"
      shift 2
      ;;
    -ds)
      skip_subfinder=true
      shift
      ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "Usage: $0 [-d target.com [-ds]] | [-f root.txt]"
      exit 1
      ;;
  esac
done

if [[ -z "$domain" && -z "$file" ]]; then
  echo "❗ Specify either -d target.com or -f root.txt"
  exit 1
fi

echo "[*] Cleaning up previous files..."
rm -f subs.txt naabu.txt alive_http_services.txt js.txt urls.txt domains.txt subdomain_takeovers_results.txt subdomain_second_takeovers_results.txt
rm -rf js_responses/
mkdir -p js_responses

# subfinder (unless skipped)
if [[ "$skip_subfinder" == false ]]; then
  echo "[1/6] subfinder — discovering subdomains"
  if [[ -n "$domain" ]]; then
    echo "[*] Target domain: $domain"
    subfinder -d "$domain" -all -silent -o subs.txt
  else
    echo "[*] Domains from file: $file"
    subfinder -dL "$file" -all -silent -o subs.txt
  fi
else
  echo "[1/6] subfinder — skipped (manual mode)"
  echo "$domain" > subs.txt
fi

# naabu
echo "[2/6] naabu — port scanning"
if [[ "$skip_subfinder" == true ]]; then
  naabu -host "$domain" -s s -tp 100 -ec -c 50 -o naabu.txt
else
  naabu -l subs.txt -s s -tp 100 -ec -c 50 -o naabu.txt
fi

# httpx
echo "[3/6] httpx — detecting active HTTP services"
httpx -l naabu.txt -rl 500 -t 200 -o alive_http_services.txt

# getJS
echo "[4/6] getJS — collecting JavaScript files"
getJS -input alive_http_services.txt -complete -threads 100 -output js.txt

# httpx + JS parsing
echo "[5/6] httpx — downloading JS and parsing URLs"
httpx -l js.txt -sr -srd js_responses/

find js_responses/response/ -type f -exec cat {} + | \
  grep -Eo 'https?://[a-zA-Z0-9._~:/?#@!$&'"'"'()*+,;=%-]+' | \
  sort -u > urls.txt

# unfurl (first stage)
echo "[*] unfurl — extracting domains from URLs (in JS)"
unfurl --unique domains < urls.txt > domains.txt

# nuclei (main check)
echo "[6/6] nuclei — subdomain takeover scan (main)"
nuclei -profile subdomain-takeovers -l domains.txt -nh -o subdomain_takeovers_results.txt

# SECOND ORDER TAKEOVER (katana)
echo "[*] SECOND ORDER — katana + unfurl + nuclei"
katana -u alive_http_services.txt -d 1 -silent -o second_order_urls.txt
unfurl --unique domains < second_order_urls.txt > second_order_domains.txt
nuclei -profile subdomain-takeovers -l second_order_domains.txt -nh -o subdomain_second_takeovers_results.txt

# Summary
echo "[✓] Done. Results:"
if [[ "$skip_subfinder" == false ]]; then
  echo "- subfinder: subs.txt ($(wc -l < subs.txt) subdomains)"
else
  echo "- subfinder: skipped, used -d $domain"
fi
echo "- naabu: naabu.txt ($(wc -l < naabu.txt) active ports)"
echo "- HTTP services: alive_http_services.txt ($(wc -l < alive_http_services.txt) hosts)"
echo "- JS files: js.txt ($(wc -l < js.txt) links)"
echo "- URLs from JS: urls.txt ($(wc -l < urls.txt) URLs)"
echo "- Domains from URLs: domains.txt ($(wc -l < domains.txt) domains)"
echo "- Takeover (3rd-order takeover from JS): subdomain_takeovers_results.txt ($(wc -l < subdomain_takeovers_results.txt) findings)"
echo "- Takeover (2nd-order takeover from katana): subdomain_second_takeovers_results.txt ($(wc -l < subdomain_second_takeovers_results.txt) findings)"
