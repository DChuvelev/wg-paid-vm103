#!/bin/sh
set -eu
MUSIC_HOST='musicserver.internal.invalid'
REPORTS_HOST='reports.secret-studio.ru'
LOCAL_HTTP='http://127.0.0.1'
REPORTS_ROOT='/srv/wg-paid/reports'
TMP="$(mktemp /tmp/vm103-public-ingress-health.XXXXXX)"
CERT="$(mktemp /tmp/vm103-public-ingress-cert.XXXXXX)"
trap 'rm -f "$TMP" "$CERT"' EXIT INT TERM

systemctl is-active --quiet caddy
command -v caddy >/dev/null 2>&1
command -v curl >/dev/null 2>&1
command -v openssl >/dev/null 2>&1
[ -d "$REPORTS_ROOT" ]
[ -f "$REPORTS_ROOT/latest/index.html" ]

ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ':(80)$'
ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ':(443)$'
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ':(2019)$'; then
    echo 'STOP_VM103_CADDY_ADMIN_LISTENER_PRESENT=true'
    exit 23
fi

code="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H "Host: $MUSIC_HOST" "$LOCAL_HTTP/health")"
[ "$code" = 200 ]
grep -Fq '"status":"ok"' "$TMP"
grep -Fq '"service":"wg-access-backend"' "$TMP"

dbcode="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H "Host: $MUSIC_HOST" "$LOCAL_HTTP/health/db")"
[ "$dbcode" = 200 ]
grep -Fq '"status":"ok"' "$TMP"
grep -Fq '"db":1' "$TMP"

unknown="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -H 'Host: wrong.internal.invalid' "$LOCAL_HTTP/health")"
[ "$unknown" = 404 ]

redirect="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -H "Host: $REPORTS_HOST" "$LOCAL_HTTP/latest/")"
[ "$redirect" = 308 ]

curl -fsS --max-time 15 --resolve "$REPORTS_HOST:443:127.0.0.1" "https://$REPORTS_HOST/latest/" -o "$TMP"
cmp -s "$TMP" "$REPORTS_ROOT/latest/index.html"

if ! printf '' | openssl s_client -connect 127.0.0.1:443 -servername "$REPORTS_HOST" 2>/dev/null | openssl x509 -outform PEM > "$CERT"; then
    echo 'STOP_VM103_TLS_CERTIFICATE_READ_FAILED=true'
    exit 24
fi
openssl x509 -in "$CERT" -noout -checkhost "$REPORTS_HOST" >/dev/null

echo 'VM103_CADDY_ACTIVE=true'
echo 'VM103_LAN_HTTP_LISTENER=true'
echo 'VM103_HTTPS_LISTENER=true'
echo 'VM103_CADDY_ADMIN_LISTENER=false'
echo 'VM103_INTERNAL_HOST_ROUTING=PASS'
echo 'VM103_INTERNAL_HEALTH_ROUTE=PASS'
echo 'VM103_INTERNAL_DB_HEALTH_ROUTE=PASS'
echo 'VM103_UNKNOWN_HOST_DENY=PASS'
echo 'VM103_REPORTS_HTTP_REDIRECT=PASS'
echo 'VM103_REPORTS_HTTPS_ROUTE=PASS'
echo 'VM103_REPORTS_LATEST_INDEX_BYTE_MATCH=PASS'
echo 'VM103_TLS_CERTIFICATE_HOSTNAME=PASS'
echo 'RESULT=PASS_VM103_PUBLIC_REPORTS_INGRESS_HEALTH'
