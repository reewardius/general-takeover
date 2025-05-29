#!/bin/bash

set -euo pipefail

# Variables
domain=""
file=""
skip_subfinder=false

# Help message
usage() {
  echo "Usage:"
  echo "  $0 -d target.com [-ds]        # scan single domain"
  echo "  $0 -f root.txt                # scan domains from file"
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d)
      [[ $# -lt 2 ]] && usage
      domain="$2"
      shift 2
      ;;
    -f)
      [[ $# -lt 2 ]] && usage
      file="$2"
      shift 2
      ;;
    -ds)
      skip_subfinder=true
      shift
      ;;
    *)
      echo "❌ Unknown argument: $1"
      usage
      ;;
  esac
done

# Validate input
if [[ -z "$domain" && -z "$file" ]]; then
  echo "❗ Specify either -d target.com or -f root.txt"
  usage
fi

# Cleanup
echo "[*] Cleaning up previous files..."
rm -f subs.txt naabu.txt alive_http_services.txt js.txt urls.txt domains.txt \
      subdomains_takeover.txt third_party_takeovers.txt subdomain_second_takeovers_results.txt \
      second_order_urls.txt second_order_domains.txt html-tool.txt html-tool-domains.txt one-subdomains-takeover.txt \
      csp-domains.txt input.txt csp-domains-takeover.txt
rm -rf js_responses/
mkdir -p js_responses

# 1. subfinder
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
  [[ -n "$domain" ]] && echo "$domain" > subs.txt
fi

# 2. naabu
echo "[2/6] naabu — port scanning"
if [[ "$skip_subfinder" == true ]]; then
  naabu -host "$domain" -s s -tp 100 -ec -c 50 -o naabu.txt
else
  naabu -l subs.txt -s s -tp 100 -ec -c 50 -o naabu.txt
fi

# 3. httpx
echo "[3/6] httpx — detecting active HTTP services"
httpx -l naabu.txt -rl 500 -t 200 -o alive_http_services.txt

# 4. getJS
echo "[4/6] getJS — collecting JavaScript files"
getJS -input alive_http_services.txt -complete -threads 100 -output js.txt

# 5. JS parsing
echo "[5/6] httpx — downloading JS and parsing URLs"
httpx -l js.txt -sr -srd js_responses/

find js_responses/response/ -type f -exec cat {} + | \
  grep -Eo 'https?://[a-zA-Z0-9._~:/?#@!$&'"'"'()*+,;=%-]+' | \
  sort -u > urls.txt

echo "[*] unfurl — extracting domains from JS URLs"
unfurl --unique domains < urls.txt > domains.txt

# 6. nuclei — subdomain takeovers
echo "[6/6] nuclei — subdomain takeover (direct subs)"
nuclei -profile subdomain-takeovers -l subs.txt -nh -o subdomains_takeover.txt

echo "[*] nuclei — third-party takeover (from JS)"
nuclei -profile subdomain-takeovers -l domains.txt -nh -o third_party_takeovers.txt

# Second-order discovery
echo "[*] katana — second-order discovery"
katana -u alive_http_services.txt -d 1 -headless -nos -silent -o second_order_urls.txt
unfurl --unique domains < second_order_urls.txt > second_order_domains.txt
nuclei -profile subdomain-takeovers -l second_order_domains.txt -nh -o subdomain_second_takeovers_results.txt

# html-tool
echo "[*] html-tool — extracting src/href from HTTP services"
html-tool attribs src href < alive_http_services.txt > html-tool.txt
unfurl --unique domains < html-tool.txt > html-tool-domains.txt

echo "[*] nuclei — takeover (html-tool domains)"
nuclei -l html-tool-domains.txt -profile subdomain-takeovers -nh -o html-subdomains-takeover.txt

# CSP-based domains
echo "[*] nuclei — takeover (CSP domains)"
cspgrabber -f alive_http_services.txt -c 200 -r 0.1 -o csp-domains.txt
awk '{gsub(/^\*\./, "", $0); print}' csp-domains.txt > input.txt
nuclei -l input.txt -profile subdomain-takeovers -nh -o csp-domains-takeover.txt

# Summary
echo -e "\n[✓] Done. Results:"
if [[ "$skip_subfinder" == false ]]; then
  echo "- subfinder: subs.txt ($(wc -l < subs.txt) subdomains)"
else
  echo "- subfinder: skipped (manual domain: $domain)"
fi
echo "- naabu: naabu.txt ($(wc -l < naabu.txt) active ports)"
echo "- HTTP services: alive_http_services.txt ($(wc -l < alive_http_services.txt) hosts)"
echo "- JS files: js.txt ($(wc -l < js.txt) links)"
echo "- URLs from JS: urls.txt ($(wc -l < urls.txt) URLs)"
echo "- Domains from URLs: domains.txt ($(wc -l < domains.txt) domains)"
echo "- Takeover (direct subs): subdomains_takeover.txt ($(wc -l < subdomains_takeover.txt) findings)"
echo "- Takeover (from JS): third_party_takeovers.txt ($(wc -l < third_party_takeovers.txt) findings)"
echo "- Takeover (katana 2nd-order): subdomain_second_takeovers_results.txt ($(wc -l < subdomain_second_takeovers_results.txt) findings)"
echo "- Takeover (html-tool 2nd-order): html-subdomains-takeover.txt ($(wc -l < html-subdomains-takeover.txt) findings)"
echo "- Takeover (CSP): csp-domains-takeover.txt ($(wc -l < csp-domains-takeover.txt) findings)"
