#!/bin/bash

set -euo pipefail

# Парсинг аргументов
domain=""
file=""

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
    *)
      echo "❌ Неизвестный аргумент: $1"
      echo "Использование: $0 [-d target.com] | [-f root.txt]"
      exit 1
      ;;
  esac
done

if [[ -z "$domain" && -z "$file" ]]; then
  echo "❗ Укажите либо -d target.com, либо -f root.txt"
  exit 1
fi

echo "[*] Очистка предыдущих файлов..."
rm -f subs.txt naabu.txt alive_http_services.txt js.txt urls.txt domains.txt subdomain_takeovers_results.txt
rm -rf js_responses/
mkdir -p js_responses

echo "[1/6] subfinder — поиск поддоменов"
if [[ -n "$domain" ]]; then
  echo "[*] Целевой домен: $domain"
  subfinder -d "$domain" -all -silent -o subs.txt
else
  echo "[*] Список доменов из файла: $file"
  subfinder -dL "$file" -all -silent -o subs.txt
fi

echo "[2/6] naabu — сканирование портов"
naabu -l subs.txt -s s -tp 100 -ec -c 50 -o naabu.txt

echo "[3/6] httpx — определение активных HTTP-сервисов"
httpx -l naabu.txt -rl 500 -t 200 -o alive_http_services.txt

echo "[4/6] getJS — сбор JavaScript-файлов"
getJS -input alive_http_services.txt -complete -output js.txt

echo "[5/6] httpx — скачивание JS и парсинг URL"
httpx -l js.txt -sr -srd js_responses/

find js_responses/responses/ -type f -exec cat {} + | \
  grep -Eo 'https?://[a-zA-Z0-9._~:/?#@!$&'"'"'()*+,;=%-]+' | \
  sort -u > urls.txt

echo "[*] unfurl — извлечение доменов из URL"
unfurl --unique domains < urls.txt > domains.txt

echo "[6/6] nuclei — поиск takeover"
nuclei -profile subdomain-takeovers -l domains.txt -nh -o subdomain_takeovers_results.txt

echo "[✓] Завершено. Результаты:"
echo "- subfinder: subs.txt ($(wc -l < subs.txt) поддоменов)"
echo "- naabu: naabu.txt ($(wc -l < naabu.txt) активных портов)"
echo "- HTTP-сервисы: alive_http_services.txt ($(wc -l < alive_http_services.txt) хостов)"
echo "- JS-файлы: js.txt ($(wc -l < js.txt) ссылок)"
echo "- URL из JS: urls.txt ($(wc -l < urls.txt) URL-ов)"
echo "- Домены из URL: domains.txt ($(wc -l < domains.txt) доменов)"
echo "- Takeover-уязвимости: subdomain_takeovers_results.txt ($(wc -l < subdomain_takeovers_results.txt) находок)"
