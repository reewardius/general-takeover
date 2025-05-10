#!/bin/bash

set -euo pipefail

# Переменные
domain=""
file=""
skip_subfinder=false

# Аргументы
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
      echo "❌ Неизвестный аргумент: $1"
      echo "Использование: $0 [-d target.com [-ds]] | [-f root.txt]"
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

# subfinder (если не skip)
if [[ "$skip_subfinder" == false ]]; then
  echo "[1/6] subfinder — поиск поддоменов"
  if [[ -n "$domain" ]]; then
    echo "[*] Целевой домен: $domain"
    subfinder -d "$domain" -all -silent -o subs.txt
  else
    echo "[*] Список доменов из файла: $file"
    subfinder -dL "$file" -all -silent -o subs.txt
  fi
else
  echo "[1/6] subfinder — пропущен (ручной режим)"
  echo "$domain" > subs.txt
fi

# naabu
echo "[2/6] naabu — сканирование портов"
if [[ "$skip_subfinder" == true ]]; then
  naabu -host "$domain" -s s -tp 100 -ec -c 50 -o naabu.txt
else
  naabu -l subs.txt -s s -tp 100 -ec -c 50 -o naabu.txt
fi

# httpx
echo "[3/6] httpx — определение активных HTTP-сервисов"
httpx -l naabu.txt -rl 500 -t 200 -o alive_http_services.txt

# getJS
echo "[4/6] getJS — сбор JavaScript-файлов"
getJS -input alive_http_services.txt -complete -output js.txt

# httpx + парсинг JS
echo "[5/6] httpx — скачивание JS и парсинг URL"
httpx -l js.txt -sr -srd js_responses/

find js_responses/response/ -type f -exec cat {} + | \
  grep -Eo 'https?://[a-zA-Z0-9._~:/?#@!$&'"'"'()*+,;=%-]+' | \
  sort -u > urls.txt

# unfurl
echo "[*] unfurl — извлечение доменов из URL"
unfurl --unique domains < urls.txt > domains.txt

# nuclei
echo "[6/6] nuclei — поиск takeover"
nuclei -profile subdomain-takeovers -l domains.txt -nh -o subdomain_takeovers_results.txt

# Итоги
echo "[✓] Завершено. Результаты:"
if [[ "$skip_subfinder" == false ]]; then
  echo "- subfinder: subs.txt ($(wc -l < subs.txt) поддоменов)"
else
  echo "- subfinder: пропущен, использован -d $domain"
fi
echo "- naabu: naabu.txt ($(wc -l < naabu.txt) активных портов)"
echo "- HTTP-сервисы: alive_http_services.txt ($(wc -l < alive_http_services.txt) хостов)"
echo "- JS-файлы: js.txt ($(wc -l < js.txt) ссылок)"
echo "- URL из JS: urls.txt ($(wc -l < urls.txt) URL-ов)"
echo "- Домены из URL: domains.txt ($(wc -l < domains.txt) доменов)"
echo "- Takeover-уязвимости: subdomain_takeovers_results.txt ($(wc -l < subdomain_takeovers_results.txt) находок)"
