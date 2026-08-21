#!/bin/sh
set -eu
HOST='musicserver.internal.invalid'
LOCAL='http://127.0.0.1'
TMP="$(mktemp /tmp/vm103-ingress-health.XXXXXX)"
trap 'rm -f "$TMP"' EXIT INT TERM

systemctl is-active --quiet caddy
command -v caddy >/dev/null 2>&1

if ! ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ':(80)$'; then
    echo 'STOP_VM103_CADDY_HTTP_LISTENER_MISSING=true'
    exit 21
fi
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ':(443)$'; then
    echo 'STOP_VM103_UNEXPECTED_HTTPS_LISTENER=true'
    exit 22
fi
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ':(2019)$'; then
    echo 'STOP_VM103_CADDY_ADMIN_LISTENER_PRESENT=true'
    exit 23
fi

code="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H "Host: $HOST" "$LOCAL/health")"
[ "$code" = 200 ]
grep -Fq '"status":"ok"' "$TMP"
grep -Fq '"service":"wg-access-backend"' "$TMP"

dbcode="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H "Host: $HOST" "$LOCAL/health/db")"
[ "$dbcode" = 200 ]
grep -Fq '"status":"ok"' "$TMP"
grep -Fq '"db":1' "$TMP"

unknown_host_code="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H 'Host: wrong.internal.invalid' "$LOCAL/health")"
[ "$unknown_host_code" = 404 ]

blocked_path_code="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H "Host: $HOST" "$LOCAL/docs")"
[ "$blocked_path_code" = 404 ]

backend_code="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' 'http://10.71.100.83:18080/health')"
[ "$backend_code" = 200 ]

echo 'VM103_CADDY_ACTIVE=true'
echo 'VM103_LAN_HTTP_LISTENER=true'
echo 'VM103_HTTPS_LISTENER=false'
echo 'VM103_CADDY_ADMIN_LISTENER=false'
echo 'VM103_INTERNAL_HOST_ROUTING=PASS'
echo 'VM103_INTERNAL_HEALTH_ROUTE=PASS'
echo 'VM103_INTERNAL_DB_HEALTH_ROUTE=PASS'
echo 'VM103_UNKNOWN_HOST_DENY=PASS'
echo 'VM103_UNLISTED_PATH_DENY=PASS'
echo 'VM103_DIRECT_VM121_UPSTREAM_HEALTH=PASS'
echo 'RESULT=PASS_VM103_INGRESS_HEALTH'
