#!/bin/sh
set -eu

export TERM="${TERM:-xterm}"
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

UUID_FILE="/etc/uuid.txt"

if [ -n "${UUID:-}" ]; then
  echo "$UUID" > "$UUID_FILE"
elif [ -f "$UUID_FILE" ]; then
  UUID="$(cat "$UUID_FILE")"
else
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  echo "$UUID" > "$UUID_FILE"
fi

INBOUND_PORT="${PORT:-10086}"
WS_PATH="${WS_PATH:-/?ed=2048}"

if [ -n "${VMESS_HOST:-}" ]; then
  HOST="$VMESS_HOST"
  PLATFORM=""
elif [ -n "${DOMAIN:-}" ]; then
  HOST="$DOMAIN"
  PLATFORM=""
elif [ -n "${VCAP_APPLICATION:-}" ]; then
  HOST="$(echo "$VCAP_APPLICATION" | jq -r '.application_uris[0] // empty' 2>/dev/null || true)"
  if [ -z "$HOST" ]; then
    HOST="$(echo "$VCAP_APPLICATION" \
      | grep -oE '"application_uris":\[[^]]+\]' \
      | sed -n 's/.*\[\s*"\([^"]\+\)".*/\1/p' | head -n1 || true)"
  fi
  PLATFORM="CloudFoundry"
elif [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  HOST="$RAILWAY_PUBLIC_DOMAIN"
  PLATFORM="Railway"
elif [ -n "${RENDER_EXTERNAL_HOSTNAME:-}" ]; then
  HOST="$RENDER_EXTERNAL_HOSTNAME"
  PLATFORM="Render"
elif [ -n "${ZEABUR_DOMAIN:-}" ]; then
  HOST="$ZEABUR_DOMAIN"
  PLATFORM="Zeabur"
elif [ -n "${KOYEB_PUBLIC_DOMAIN:-}" ]; then
  HOST="$KOYEB_PUBLIC_DOMAIN"
  PLATFORM="Koyeb"
else
  HOST="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
          curl -s --max-time 5 https://ip.sb 2>/dev/null || \
          echo 'your-domain.com')"
  PLATFORM=""
fi

COUNTRY="$(curl -s --max-time 5 https://ipapi.co/country 2>/dev/null || echo '')"

if [ -n "${PS_NAME:-}" ]; then
  PS_NAME="$PS_NAME"
elif [ -n "$PLATFORM" ]; then
  PS_NAME="${COUNTRY:+${COUNTRY}-}${PLATFORM}"
else
  ASN_ORG="$(curl -s --max-time 5 https://ipapi.co/org 2>/dev/null || echo '')"
  ASN_ORG="$(echo "$ASN_ORG" \
    | sed 's/^AS[0-9]* //' \
    | sed 's/,\? *Inc\.$//' \
    | sed 's/,\? *LLC\.*//' \
    | sed 's/,\? *Ltd\.*//' \
    | sed 's/,\? *Corp\.*//' \
    | sed 's/ *$//' \
    | cut -c1-20)"
  if [ -n "$COUNTRY" ] && [ -n "$ASN_ORG" ]; then
    PS_NAME="${COUNTRY}-${ASN_ORG}"
  elif [ -n "$COUNTRY" ]; then
    PS_NAME="${COUNTRY}-mous"
  else
    PS_NAME="mous"
  fi
fi

cat > /etc/v2ray-config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${INBOUND_PORT},
    "listen": "0.0.0.0",
    "protocol": "vmess",
    "settings": {
      "clients": [{ "id": "${UUID}", "alterId": 0 }]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "${WS_PATH}" }
    }
  }],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF

VMESS_JSON="$(cat <<EOT
{
  "v": "2",
  "ps": "${PS_NAME}",
  "add": "${HOST}",
  "port": "443",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${HOST}",
  "path": "${WS_PATH}",
  "tls": "tls"
}
EOT
)"

VMESS_LINK="vmess://$(printf '%s' "$VMESS_JSON" | base64 -w 0 2>/dev/null || printf '%s' "$VMESS_JSON" | base64)"

echo "================= VMESS ================="
echo "$VMESS_LINK"
echo "========================================="

V2RAY_BIN=""
if command -v v2ray >/dev/null 2>&1; then
  V2RAY_BIN="$(command -v v2ray)"
else
  for p in /usr/local/bin/v2ray /usr/bin/v2ray /usr/local/v2ray/v2ray; do
    [ -x "$p" ] && V2RAY_BIN="$p" && break
  done
fi

if [ -z "$V2RAY_BIN" ]; then
  echo "FATAL: v2ray 未找到"
  exit 127
fi

exec "$V2RAY_BIN" run -config /etc/v2ray-config.json
