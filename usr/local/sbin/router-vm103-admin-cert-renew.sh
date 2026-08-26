#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DOMAIN='admin.secret-studio.ru'
EMAIL='vpn@secret-studio.ru'
LEGO='/usr/local/bin/lego'
STATE='/var/lib/wg-paid/admin-acme'
SECRETS='/etc/wg-paid/secrets/nicru-acme'
LIVE='/etc/caddy/admin-tls'
SRC_CERT="$STATE/certificates/${DOMAIN}.crt"
SRC_KEY="$STATE/certificates/${DOMAIN}.key"
LIVE_CERT="$LIVE/${DOMAIN}.crt"
LIVE_KEY="$LIVE/${DOMAIN}.key"

for f in user password service_id secret; do
  test -s "$SECRETS/$f"
  test "$(stat -c '%a' "$SECRETS/$f")" = 600
done

test -x "$LEGO"
export NICRU_USER_FILE="$SECRETS/user"
export NICRU_PASSWORD_FILE="$SECRETS/password"
export NICRU_SERVICE_ID_FILE="$SECRETS/service_id"
export NICRU_SECRET_FILE="$SECRETS/secret"

before='absent'
if test -s "$SRC_CERT"; then
  before="$(sha256sum "$SRC_CERT" | awk '{print $1}')"
fi

"$LEGO" run \
  --path "$STATE" \
  --server letsencrypt \
  --email "$EMAIL" \
  --accept-tos \
  --dns nicru \
  --dns.resolvers 1.1.1.1:53 \
  --dns.resolvers 8.8.8.8:53 \
  --domains "$DOMAIN" \
  --renew-days 30

test -s "$SRC_CERT"
test -s "$SRC_KEY"
openssl x509 -in "$SRC_CERT" -noout -checkend 2592000 >/dev/null
openssl x509 -in "$SRC_CERT" -noout -ext subjectAltName | grep -Fq "DNS:${DOMAIN}"

after="$(sha256sum "$SRC_CERT" | awk '{print $1}')"
if test "$before" != "$after" || ! test -s "$LIVE_CERT" || ! cmp -s "$SRC_CERT" "$LIVE_CERT" || ! cmp -s "$SRC_KEY" "$LIVE_KEY"; then
  install -d -o root -g caddy -m 0750 "$LIVE"
  install -o root -g caddy -m 0640 "$SRC_CERT" "$LIVE_CERT"
  install -o root -g caddy -m 0640 "$SRC_KEY" "$LIVE_KEY"
  if grep -Fq "$LIVE_CERT $LIVE_KEY" /etc/caddy/Caddyfile; then
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
    systemctl restart caddy
    systemctl is-active --quiet caddy
  fi
fi

echo RESULT=PASS_VM103_ADMIN_CERT_RENEW
