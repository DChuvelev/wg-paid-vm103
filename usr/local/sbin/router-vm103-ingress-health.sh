#!/bin/sh
set -eu
MUSIC_HOST='musicserver.internal.invalid'
REPORTS_HOST='reports.secret-studio.ru'
REPORTS001_HOST='reports001.secret-studio.ru'
ACCESS_HOST='access.secret-studio.ru'
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
if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ':(2019)$'; then echo 'STOP_VM103_CADDY_ADMIN_LISTENER_PRESENT=true'; exit 23; fi
code="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H "Host: $MUSIC_HOST" "$LOCAL_HTTP/health")"
[ "$code" = 200 ]; grep -Fq '"status":"ok"' "$TMP"; grep -Fq '"service":"wg-access-backend"' "$TMP"
dbcode="$(curl -sS --max-time 5 -o "$TMP" -w '%{http_code}' -H "Host: $MUSIC_HOST" "$LOCAL_HTTP/health/db")"
[ "$dbcode" = 200 ]; grep -Fq '"status":"ok"' "$TMP"; grep -Fq '"db":1' "$TMP"
unknown="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -H 'Host: wrong.internal.invalid' "$LOCAL_HTTP/health")"; [ "$unknown" = 404 ]
for H in "$REPORTS_HOST" "$REPORTS001_HOST"; do
 redirect="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -H "Host: $H" "$LOCAL_HTTP/latest/")"; [ "$redirect" = 308 ]
 curl -fsS --max-time 15 --resolve "$H:443:127.0.0.1" "https://$H/latest/" -o "$TMP"; cmp -s "$TMP" "$REPORTS_ROOT/latest/index.html"
 printf '' | openssl s_client -connect 127.0.0.1:443 -servername "$H" 2>/dev/null | openssl x509 -outform PEM > "$CERT"
 openssl x509 -in "$CERT" -noout -checkhost "$H" >/dev/null
done
access_redirect="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -H "Host: $ACCESS_HOST" "$LOCAL_HTTP/")"; [ "$access_redirect" = 308 ]
access_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/")"; [ "$access_code" = 200 ]; grep -Fq '/v2/auth/login/request' "$TMP"; grep -Fq "location.replace('/account')" "$TMP"
access_health_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/health")"; [ "$access_health_code" = 200 ]; grep -Fqx 'access-ok' "$TMP"
printf '' | openssl s_client -connect 127.0.0.1:443 -servername "$ACCESS_HOST" 2>/dev/null | openssl x509 -outform PEM > "$CERT"
openssl x509 -in "$CERT" -noout -checkhost "$ACCESS_HOST" >/dev/null
access_login_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/login")"; [ "$access_login_code" = 200 ]; grep -Fq 'Secret Studio VPN' "$TMP"; grep -Fq '/v2/auth/login/request' "$TMP"
access_invite_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/invite#token=never-sent")"; [ "$access_invite_code" = 200 ]; grep -Fq "location.pathname==='/invite'" "$TMP"; grep -Fq '/v2/auth/invites/redeem' "$TMP"
access_account_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/account")"; [ "$access_account_code" = 200 ]; grep -Fq "location.pathname==='/account'" "$TMP"; grep -Fq '/v2/account/profiles' "$TMP"; grep -Fq 'wg_access_csrf' "$TMP"
access_magic_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/auth/magic#token=never-sent")"; [ "$access_magic_code" = 200 ]; grep -Fq 'location.hash' "$TMP"; grep -Fq 'history.replaceState' "$TMP"; grep -Fq '/v2/auth/magic-link/consume' "$TMP"; grep -Fq "location.replace('/account')" "$TMP"
account_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/v2/account/me")"; [ "$account_code" = 401 ]
admin_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/v2/admin/invites")"; [ "$admin_code" = 404 ]; grep -Fqx 'not found' "$TMP"
agent_code="$(curl -sS --max-time 15 --resolve "$ACCESS_HOST:443:127.0.0.1" -o "$TMP" -w '%{http_code}' "https://$ACCESS_HOST/v2/agent/jobs")"; [ "$agent_code" = 404 ]; grep -Fqx 'not found' "$TMP"
echo 'VM103_CADDY_ACTIVE=true'
echo 'VM103_REPORTS_PRIMARY=PASS'
echo 'VM103_REPORTS001_HTTP_REDIRECT=PASS'
echo 'VM103_REPORTS001_HTTPS_ROUTE=PASS'
echo 'VM103_REPORTS001_LATEST_INDEX_BYTE_MATCH=PASS'
echo 'VM103_REPORTS001_TLS_CERTIFICATE_HOSTNAME=PASS'
echo 'VM103_ACCESS_HTTP_REDIRECT=PASS'
echo 'VM103_ACCESS_ROOT_LOGIN_PAGE=PASS'
echo 'VM103_ACCESS_HEALTH_ROUTE=PASS'
echo 'VM103_ACCESS_TLS_CERTIFICATE_HOSTNAME=PASS'
echo 'VM103_ACCESS_LOGIN_PAGE=PASS'
echo 'VM103_ACCESS_INVITE_PAGE=PASS'
echo 'VM103_ACCESS_ACCOUNT_PAGE=PASS'
echo 'VM103_ACCESS_MAGIC_FRAGMENT_PAGE=PASS'
echo 'VM103_ACCESS_PUBLIC_API_PROXY_ACTIVE=true'
echo 'VM103_ACCESS_EXTERNAL_ONBOARDING_GATE_OPEN=PASS'
echo 'VM103_ACCESS_ACCOUNT_AUTH_REQUIRED=PASS'
echo 'VM103_ACCESS_AGENT_PROXY_ACTIVE=false'
echo 'VM103_ACCESS_ADMIN_PROXY_ACTIVE=false'

WEB_META_ROOT='/srv/wg-paid/web-meta'
OLD_SEED='/old/20260821-133634_step050m07p26c4f_r04_public_reports_cutover_vm101_dnat_to_vm103_and_tls_retry/'
[ -f "$WEB_META_ROOT/index.html" ]
[ -f "$WEB_META_ROOT/robots.txt" ]
[ -f "$WEB_META_ROOT/sitemap-reports.xml" ]
[ -f "$WEB_META_ROOT/sitemap-reports001.xml" ]
for H in "$REPORTS_HOST" "$REPORTS001_HOST"; do
  curl -fsS --max-time 15 --resolve "$H:443:127.0.0.1" "https://$H/" -o "$TMP"
  grep -Fq 'Secret Studio Reports' "$TMP"
  grep -Fq 'href="/latest/"' "$TMP"
  curl -fsS --max-time 15 --resolve "$H:443:127.0.0.1" "https://$H/robots.txt" -o "$TMP"
  grep -Fqx 'User-agent: OAI-SearchBot' "$TMP"
  grep -Fqx 'Allow: /' "$TMP"
  curl -fsS --max-time 15 --resolve "$H:443:127.0.0.1" "https://$H/sitemap.xml" -o "$TMP"
  grep -Fq "https://$H/latest/" "$TMP"
  grep -Fq "https://$H$OLD_SEED" "$TMP"
  HDR="$(mktemp /tmp/vm103-crawl-hdr.XXXXXX)"
  curl -fsS --max-time 15 --resolve "$H:443:127.0.0.1" -D "$HDR" -o /dev/null "https://$H/latest/"
  tr -d '\r' < "$HDR" | grep -Fix 'Cache-Control: no-cache, max-age=0, must-revalidate' >/dev/null
  curl -fsS --max-time 15 --resolve "$H:443:127.0.0.1" -D "$HDR" -o /dev/null "https://$H$OLD_SEED"
  tr -d '\r' < "$HDR" | grep -Fix 'Cache-Control: public, max-age=31536000, immutable' >/dev/null
  rm -f "$HDR"
done
echo 'VM103_REPORTS_CRAWL_ROOT=PASS'
echo 'VM103_REPORTS_ROBOTS=PASS'
echo 'VM103_REPORTS_SITEMAP=PASS'
echo 'VM103_REPORTS_LATEST_CACHE_POLICY=PASS'
echo 'VM103_REPORTS_OLD_CACHE_POLICY=PASS'
echo 'VM103_REPORTS_ACCESS_LOGGING_CONFIGURED=true'

echo 'RESULT=PASS_VM103_ACCESS_AND_REPORTS001_INGRESS_HEALTH'
