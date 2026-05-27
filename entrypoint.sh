#!/bin/sh
set -eu

export TERM="${TERM:-xterm}"
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

UUID_FILE="/etc/uuid.txt"

# UUID 管理（可通过环境变量 UUID 注入，否则自动生成）
if [ -n "${UUID:-}" ]; then
  echo "$UUID" > "$UUID_FILE"
elif [ -f "$UUID_FILE" ]; then
  UUID="$(cat "$UUID_FILE")"
else
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  echo "$UUID" > "$UUID_FILE"
fi

# ↓ 监听端口，默认 10086，可通过环境变量 PORT 修改
INBOUND_PORT="${PORT:-10086}"

# ↓ WebSocket 路径，默认 /laoluo，可通过环境变量 WS_PATH 修改
WS_PATH="${WS_PATH:-/laoluo}"

# 自动识别各平台域名（优先级从高到低）
if [ -n "${VMESS_HOST:-}" ]; then
  # 手动指定（最高优先级）
  HOST="$VMESS_HOST"
elif [ -n "${DOMAIN:-}" ]; then
  # 手动指定域名
  HOST="$DOMAIN"
elif [ -n "${VCAP_APPLICATION:-}" ]; then
  # Cloud Foundry（IBM Cloud、SAP BTP等）
  HOST="$(echo "$VCAP_APPLICATION" | jq -r '.application_uris[0] // empty' 2>/dev/null || true)"
  if [ -z "$HOST" ]; then
    HOST="$(echo "$VCAP_APPLICATION" \
      | grep -oE '"application_uris":\[[^]]+\]' \
      | sed -n 's/.*\[\s*"\([^"]\+\)".*/\1/p' | head -n1 || true)"
  fi
elif [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  # Railway
  HOST="$RAILWAY_PUBLIC_DOMAIN"
elif [ -n "${RENDER_EXTERNAL_HOSTNAME:-}" ]; then
  # Render
  HOST="$RENDER_EXTERNAL_HOSTNAME"
elif [ -n "${ZEABUR_DOMAIN:-}" ]; then
  # Zeabur
  HOST="$ZEABUR_DOMAIN"
elif [ -n "${KOYEB_PUBLIC_DOMAIN:-}" ]; then
  # Koyeb
  HOST="$KOYEB_PUBLIC_DOMAIN"
else
  # 自动获取公网 IP 兜底
  HOST="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
          curl -s --max-time 5 https://ip.sb 2>/dev/null || \
          echo 'your-domain.com')"
fi

# 自动识别平台名称
if [ -n "${PS_NAME:-}" ]; then
  # ↓ 手动指定节点名称（最高优先级），部署时传入 PS_NAME 环境变量
  PS_NAME="$PS_NAME"
elif [ -n "${VCAP_APPLICATION:-}" ]; then
  PS_NAME="CloudFoundry"
elif [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  PS_NAME="Railway"
elif [ -n "${RENDER_EXTERNAL_HOSTNAME:-}" ]; then
  PS_NAME="Render"
elif [ -n "${ZEABUR_DOMAIN:-}" ]; then
  PS_NAME="Zeabur"
elif [ -n "${KOYEB_PUBLIC_DOMAIN:-}" ]; then
  PS_NAME="Koyeb"
else
  PS_NAME="mous"
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
