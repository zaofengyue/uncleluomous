#!/bin/sh
set -eu

# 避免 clear/终端能力报错
export TERM="${TERM:-xterm}"
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

UUID_FILE="/etc/uuid.txt"

# ==== 版权信息横幅 ====
cat <<'EOF'
----------------------------------------------------------------
🚀📺⚠️  YOUTUBE频道：Uncle LUO老罗叔叔的数字生活指南 ｜ 项目：SAP-VPN ｜ 直连简化版  🚀📺⚠️
声明：仅供学习与隐私保护使用，请遵守当地法律法规与平台条款。
关键词：Uncle LUO、老罗叔叔、数字生活指南
----------------------------------------------------------------
EOF
echo "油管频道：老罗叔叔｜SAP-VPN直连版"

# ==== UUID 管理（可外部注入 UUID；否则持久化到 /etc/uuid.txt）====
if [ -n "${UUID:-}" ]; then
  echo "$UUID" > "$UUID_FILE"
elif [ -f "$UUID_FILE" ]; then
  UUID="$(cat "$UUID_FILE")"
else
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  echo "$UUID" > "$UUID_FILE"
fi

# ==== 端口与 WS 路径 ====
# 在 Cloud Foundry 下，路由器会把外部请求经 443/TLS 终止，再以 HTTP->container 的形式转发到 $PORT
INBOUND_PORT="${PORT:-10086}"
WS_PATH="${WS_PATH:-/laoluo}"

# ==== 域名/Host（优先顺序：VCAP -> VMESS_HOST -> DOMAIN -> 默认提示串）====
VMESS_HOST="${VMESS_HOST:-}"
DOMAIN="${DOMAIN:-}"

if [ -n "${VCAP_APPLICATION:-}" ]; then
  # 优先解析 VCAP_APPLICATION.application_uris[0]
  # 有 jq 更稳；若失败则用 grep/sed 兜底
  HOST_FROM_VCAP="$(echo "$VCAP_APPLICATION" | jq -r '.application_uris[0] // empty' 2>/dev/null || true)"
  if [ -z "$HOST_FROM_VCAP" ]; then
    HOST_FROM_VCAP="$(echo "$VCAP_APPLICATION" \
      | grep -oE '"application_uris":\[[^]]+\]' \
      | sed -n 's/.*\[\s*"\([^"]\+\)".*/\1/p' | head -n1 || true)"
  fi
  ROUTE_HOST="$HOST_FROM_VCAP"
else
  ROUTE_HOST=""
fi

HOST="${VMESS_HOST:-${DOMAIN:-$ROUTE_HOST}}"
if [ -z "$HOST" ]; then
  HOST="your-domain.com"
fi

# ==== 生成 v2ray 配置（vmess + ws，无 tls；CF 路由层终止 tls）====
cat > /etc/v2ray-config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": ${INBOUND_PORT},
    "listen": "0.0.0.0",
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "${UUID}",
        "alterId": 0
      }]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "${WS_PATH}"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

# ==== 生成 VMess 链接（备注名：油管频道：老罗叔叔｜SAP-VPN直连版）====
# 客户端连接：443 + tls，由 CF 终止后转发到容器 $PORT
PS_NAME="油管频道：老罗叔叔｜SAP-VPN直连版"

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

# base64 一行输出，避免换行导致二维码失效
VMESS_LINK="vmess://$(printf '%s' "$VMESS_JSON" | base64 -w 0 2>/dev/null || printf '%s' "$VMESS_JSON" | base64)"

# ==== 展示信息 ====
echo "================= VMESS (DIRECT) ================="
echo "$VMESS_LINK"
echo "=================================================="

# 打印二维码（没有 qrencode 也不报错）
if command -v qrencode >/dev/null 2>&1; then
  echo "===== SAP-VPN ====="
  qrencode -t ANSIUTF8 "$VMESS_LINK" || echo "(二维码渲染失败，但链接可用)"
  echo "=================================================="
else
  echo "(未安装 qrencode，跳过二维码打印)"
fi

# ====== 自动探测 v2ray 可执行文件 ======
V2RAY_BIN=""
if command -v v2ray >/dev/null 2>&1; then
  V2RAY_BIN="$(command -v v2ray)"
else
  for p in /usr/local/bin/v2ray /usr/bin/v2ray /usr/local/v2ray/v2ray /usr/local/v2ray; do
    [ -x "$p" ] && V2RAY_BIN="$p" && break
  done
fi

if [ -z "$V2RAY_BIN" ]; then
  echo "FATAL: v2ray 可执行文件未找到。请检查镜像内 /usr/local/ 与 /usr/local/bin/。"
  exit 127
fi

# ====== 启动 v2ray ======
exec "$V2RAY_BIN" run -config /etc/v2ray-config.json
