#!/bin/bash

set -euo pipefail

# Variables
domain=""
file=""
skip_subfinder=false
skip_getjs=false
skip_js_parsing=false
skip_nuclei=false
skip_second_order=false
skip_html_tool=false
skip_csp=false

# Help message
usage() {
  echo "Usage:"
  echo "  $0 -d target.com [options]    # scan single domain"
  echo "  $0 -f root.txt [options]      # scan domains from file"
  echo ""
  echo "Options:"
  echo "  -ds          Skip subfinder (manual domain mode)"
  echo "  -sg          Skip getJS JavaScript collection"
  echo "  -sj          Skip JavaScript parsing and URL extraction"
  echo "  -snuc        Skip basic nuclei subdomain takeover checks"
  echo "  -sso         Skip second-order discovery (katana)"
  echo "  -sht         Skip html-tool extraction"
  echo "  -scsp        Skip CSP-based domain extraction"
  echo ""
  echo "Examples:"
  echo "  $0 -d example.com                    # full scan"
  echo "  $0 -d example.com -ds -sg            # skip subfinder and getJS"
  echo "  $0 -f domains.txt -sj -sso           # skip JS parsing and 2nd-order"
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
    -sg)
      skip_getjs=true
      shift
      ;;
    -sj)
      skip_js_parsing=true
      shift
      ;;
    -snuc)
      skip_nuclei=true
      shift
      ;;
    -sso)
      skip_second_order=true
      shift
      ;;
    -sht)
      skip_html_tool=true
      shift
      ;;
    -scsp)
      skip_csp=true
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
      csp-domains.txt input.txt csp-domains-takeover.txt html-subdomains-takeover.txt
rm -rf js_responses/
mkdir -p js_responses

# 1. subfinder
if [[ "$skip_subfinder" == false ]]; then
  echo "[1/9] subfinder — discovering subdomains"
  if [[ -n "$domain" ]]; then
    echo "[*] Target domain: $domain"
    subfinder -d "$domain" -all -silent -o subs.txt
  else
    echo "[*] Domains from file: $file"
    subfinder -dL "$file" -all -silent -o subs.txt
  fi
else
  echo "[1/9] subfinder — skipped (manual mode)"
  if [[ -n "$domain" ]]; then
    echo "$domain" > subs.txt
  else
    cp "$file" subs.txt
  fi
fi

# 2. naabu
echo "[2/7] naabu — port scanning"
if [[ "$skip_subfinder" == true && -n "$domain" ]]; then
  naabu -host "$domain" -s s -tp 100 -ec -c 50 -o naabu.txt
else
  naabu -l subs.txt -s s -tp 100 -ec -c 50 -o naabu.txt
fi

# 3. httpx
echo "[3/7] httpx — detecting active HTTP services"
httpx -l naabu.txt -rl 500 -t 200 -o alive_http_services.txt

# 4. getJS
if [[ "$skip_getjs" == false ]]; then
  echo "[4/7] getJS — collecting JavaScript files"
  getJS -input alive_http_services.txt -complete -threads 100 -output js.txt
else
  echo "[4/7] getJS — skipped"
  touch js.txt
fi

# 5. JS parsing
if [[ "$skip_js_parsing" == false ]]; then
  echo "[5/7] httpx — downloading JS and parsing URLs"
  if [[ -s js.txt ]]; then
    httpx -l js.txt -sr -srd js_responses/
    
    find js_responses/response/ -type f -exec cat {} + 2>/dev/null | \
      grep -Eo 'https?://[a-zA-Z0-9._~:/?#@!$&'"'"'()*+,;=%-]+' | \
      sort -u > urls.txt || touch urls.txt
    
    echo "[*] unfurl — extracting domains from JS URLs"
    if [[ -s urls.txt ]]; then
      unfurl --unique domains < urls.txt > domains.txt
    else
      touch domains.txt
    fi
  else
    echo "[*] No JS files to process"
    touch urls.txt domains.txt
  fi
else
  echo "[5/7] JS parsing — skipped"
  touch urls.txt domains.txt
fi

# 6. nuclei — subdomain takeovers
if [[ "$skip_nuclei" == false ]]; then
  echo "[6/7] nuclei — subdomain takeover (direct subs)"
  nuclei -profile subdomain-takeovers -l subs.txt -nh -o subdomains_takeover.txt
  
  echo "[*] nuclei — third-party takeover (from JS)"
  if [[ -s domains.txt ]]; then
    nuclei -profile subdomain-takeovers -l domains.txt -nh -o third_party_takeovers.txt
  else
    touch third_party_takeovers.txt
  fi
else
  echo "[6/7] nuclei — skipped"
  touch subdomains_takeover.txt third_party_takeovers.txt
fi

# Second-order discovery
if [[ "$skip_second_order" == false ]]; then
  echo "[7/7] katana — second-order discovery"
  if [[ -s alive_http_services.txt ]]; then
    katana -u alive_http_services.txt -d 1 -headless -nos -silent -o second_order_urls.txt
    if [[ -s second_order_urls.txt ]]; then
      unfurl --unique domains < second_order_urls.txt > second_order_domains.txt
      if [[ "$skip_nuclei" == false && -s second_order_domains.txt ]]; then
        nuclei -profile subdomain-takeovers -l second_order_domains.txt -nh -o subdomain_second_takeovers_results.txt
      else
        touch subdomain_second_takeovers_results.txt
      fi
    else
      touch second_order_domains.txt subdomain_second_takeovers_results.txt
    fi
  else
    touch second_order_urls.txt second_order_domains.txt subdomain_second_takeovers_results.txt
  fi
else
  echo "[7/7] katana — skipped"
  touch second_order_urls.txt second_order_domains.txt subdomain_second_takeovers_results.txt
fi

# html-tool
if [[ "$skip_html_tool" == false ]]; then
  echo "[*] html-tool — extracting src/href from HTTP services"
  if [[ -s alive_http_services.txt ]]; then
    html-tool attribs src href < alive_http_services.txt > html-tool.txt
    if [[ -s html-tool.txt ]]; then
      unfurl --unique domains < html-tool.txt > html-tool-domains.txt
      
      echo "[*] nuclei — takeover (html-tool domains)"
      if [[ "$skip_nuclei" == false && -s html-tool-domains.txt ]]; then
        nuclei -l html-tool-domains.txt -profile subdomain-takeovers -nh -o html-subdomains-takeover.txt
      else
        touch html-subdomains-takeover.txt
      fi
    else
      touch html-tool-domains.txt html-subdomains-takeover.txt
    fi
  else
    touch html-tool.txt html-tool-domains.txt html-subdomains-takeover.txt
  fi
else
  echo "[*] html-tool — skipped"
  touch html-tool.txt html-tool-domains.txt html-subdomains-takeover.txt
fi

# CSP-based domains
if [[ "$skip_csp" == false ]]; then
  echo "[*] nuclei — takeover (CSP domains)"
  if [[ -s alive_http_services.txt ]]; then
    cspgrabber -f alive_http_services.txt -c 200 -r 0.1 -o csp-domains.txt
    if [[ -s csp-domains.txt ]]; then
      awk '{gsub(/^\*\./, "", $0); print}' csp-domains.txt > input.txt
      if [[ "$skip_nuclei" == false && -s input.txt ]]; then
        nuclei -l input.txt -profile subdomain-takeovers -nh -o csp-domains-takeover.txt
      else
        touch csp-domains-takeover.txt
      fi
    else
      touch input.txt csp-domains-takeover.txt
    fi
  else
    touch csp-domains.txt input.txt csp-domains-takeover.txt
  fi
else
  echo "[*] CSP domains — skipped"
  touch csp-domains.txt input.txt csp-domains-takeover.txt
fi

# Summary
echo -e "\n[✓] Done. Results:"
if [[ "$skip_subfinder" == false ]]; then
  echo "- subfinder: subs.txt ($(wc -l < subs.txt 2>/dev/null || echo 0) subdomains)"
else
  echo "- subfinder: skipped (manual domain: ${domain:-$file})"
fi

echo "- naabu: naabu.txt ($(wc -l < naabu.txt 2>/dev/null || echo 0) active ports)"
echo "- HTTP services: alive_http_services.txt ($(wc -l < alive_http_services.txt 2>/dev/null || echo 0) hosts)"

if [[ "$skip_getjs" == false ]]; then
  echo "- JS files: js.txt ($(wc -l < js.txt 2>/dev/null || echo 0) links)"
else
  echo "- getJS: skipped"
fi

if [[ "$skip_js_parsing" == false ]]; then
  echo "- URLs from JS: urls.txt ($(wc -l < urls.txt 2>/dev/null || echo 0) URLs)"
  echo "- Domains from URLs: domains.txt ($(wc -l < domains.txt 2>/dev/null || echo 0) domains)"
else
  echo "- JS parsing: skipped"
fi

if [[ "$skip_nuclei" == false ]]; then
  echo "- Takeover (basic direct subs): subdomains_takeover.txt ($(wc -l < subdomains_takeover.txt 2>/dev/null || echo 0) findings)"
  echo "- Takeover (from JS): third_party_takeovers.txt ($(wc -l < third_party_takeovers.txt 2>/dev/null || echo 0) findings)"
  echo "- Takeover (katana 2nd-order): subdomain_second_takeovers_results.txt ($(wc -l < subdomain_second_takeovers_results.txt 2>/dev/null || echo 0) findings)"
  echo "- Takeover (html-tool 2nd-order): html-subdomains-takeover.txt ($(wc -l < html-subdomains-takeover.txt 2>/dev/null || echo 0) findings)"
  echo "- Takeover (CSP): csp-domains-takeover.txt ($(wc -l < csp-domains-takeover.txt 2>/dev/null || echo 0) findings)"
else
  echo "- nuclei: skipped"
fi

if [[ "$skip_second_order" == true ]]; then
  echo "- Second-order discovery: skipped"
fi

if [[ "$skip_html_tool" == true ]]; then
  echo "- html-tool: skipped"
fi

if [[ "$skip_csp" == true ]]; then
  echo "- CSP domains: skipped"
fi
