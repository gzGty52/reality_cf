#!/usr/bin/env bash

set -Eeuo pipefail

XRAY_CONFIG="/usr/local/etc/xray/config.json"
REALITY_SERVER_NAME="speed.cloudflare.com"
REALITY_DEST="${REALITY_SERVER_NAME}:443"
REALITY_PORT=443

die() {
    echo "错误：$*" >&2
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 用户运行此脚本。"
fi

for command_name in curl openssl awk systemctl; do
    command -v "${command_name}" >/dev/null 2>&1 || die "缺少命令：${command_name}"
done

echo "====== 安装 Xray Reality 节点 ======"

bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

command -v xray >/dev/null 2>&1 || die "Xray 安装失败，未找到 xray 命令。"

echo "====== 生成 Reality 参数 ======"

UUID="$(xray uuid)"
KEYS="$(xray x25519)"

# 兼容新版的“Private key/Public key”和旧版的“PrivateKey/Password”。
PRIVATE_KEY="$(awk -F':[[:space:]]*' '/Private[[:space:]]*[Kk]ey|PrivateKey/ {print $2; exit}' <<<"${KEYS}")"
PUBLIC_KEY="$(awk -F':[[:space:]]*' '/Public[[:space:]]*[Kk]ey|Password/ {print $2; exit}' <<<"${KEYS}")"
SHORT_ID="$(openssl rand -hex 4)"

[[ -n "${PRIVATE_KEY}" ]] || die "无法从 xray x25519 输出中读取 PrivateKey。"
[[ -n "${PUBLIC_KEY}" ]] || die "无法从 xray x25519 输出中读取 PublicKey。"

IP="$(curl -4fsS https://api.ipify.org || curl -6fsS https://api64.ipify.org)"
[[ -n "${IP}" ]] || die "无法获取服务器公网 IP。"

CLIENT_HOST="${IP}"
if [[ "${IP}" == *:* ]]; then
    CLIENT_HOST="[${IP}]"
fi

echo "====== 写入 Xray 配置 ======"

install -d -m 0755 "$(dirname "${XRAY_CONFIG}")"

cat >"${XRAY_CONFIG}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "dokodemo-in",
      "port": ${REALITY_PORT},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 4431,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 4431,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": [
            "${REALITY_SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "domain": [
          "${REALITY_SERVER_NAME}"
        ],
        "outboundTag": "direct"
      },
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

echo "====== 检查并启动 Xray ======"

xray run -test -config "${XRAY_CONFIG}"
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

systemctl is-active --quiet xray || die "Xray 启动失败，请运行 journalctl -u xray 查看日志。"

REALITY_LINK="vless://${UUID}@${CLIENT_HOST}:${REALITY_PORT}?encryption=none&security=reality&sni=${REALITY_SERVER_NAME}&fp=safari&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#Reality"

echo
echo "===== Reality 节点安装完成 ====="
echo
echo "地址: ${IP}"
echo "端口: ${REALITY_PORT}"
echo "UUID: ${UUID}"
echo "PublicKey: ${PUBLIC_KEY}"
echo "ShortId: ${SHORT_ID}"
echo "SNI: ${REALITY_SERVER_NAME}"
echo "Flow: xtls-rprx-vision"
echo
echo "Reality 分享链接:"
echo "${REALITY_LINK}"
echo

simple_tuning() {
    echo "====== 执行简易调优 ======"

    cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
# BBR Optimization
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    modprobe tcp_bbr 2>/dev/null || true
    sysctl --system

    echo
    echo "简易调优完成。"
    sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control
}

dynamic_tuning() {
    echo "====== 执行动态调优 ======"
    bash <(curl -fsSL https://raw.githubusercontent.com/Kylin010/tcpfit/main/tcpfit.sh)
}

while true; do
    echo "请选择后续操作："
    echo "1. 简易调优"
    echo "2. 动态调优"
    echo "0. 退出"
    read -r -p "请输入选项 [0-2]: " CHOICE

    case "${CHOICE}" in
        1)
            simple_tuning
            break
            ;;
        2)
            dynamic_tuning
            break
            ;;
        0)
            echo "已退出。"
            break
            ;;
        *)
            echo "无效选项，请重新输入。"
            echo
            ;;
    esac
done
