#!/bin/sh
set -eu

export TERM="${TERM:-xterm}"
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

UUID_FILE="/etc/uuid.txt"

# UUID 管理
if [ -n "${UUID:-}" ]; then
  echo "$UUID" > "$UUID_FILE"
elif [ -f "$UUID_FILE" ]; then
  UUID="$(cat "$UUID_FILE")"
else
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  echo "$UUID" > "$UUID_FILE"
fi

# 端口与 WS 路径
INBOUND_PORT="${PORT:-10086}"
WS_PATH="${WS_PATH:-/fengyue}"

# 域名
VMESS_HOST="${VMESS_HOST:-}"
DOMAIN="${DOMAIN:-}"
HOST="${VMESS_HOST:-${DOMAIN:-}}"
if [ -z "$HOST" ]; then
  HOST="your-domain.com"
fi

# 生成 v2ray 配置
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

# 生成 VMess 链接
VMESS_JSON="$(cat <<EOT
{
  "v": "2",
  "ps": "APP",
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

# 启动 v2ray
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
