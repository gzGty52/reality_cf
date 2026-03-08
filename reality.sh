
#!/bin/bash

set -e


echo "====== 开启 BBR ======"

cat >> /etc/sysctl.conf <<EOF

# BBR Optimization
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl -p

echo "====== 安装 Xray ======"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root


echo "====== 生成 UUID ======"

UUID=$(xray uuid)


echo "====== 生成 Reality 密钥 ======"

KEYS=$(xray x25519)

PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep Password | awk '{print $2}')


echo "====== 生成 shortId ======"

SHORT_ID=$(openssl rand -hex 4)


echo "====== 获取服务器IP ======"

IP=$(curl -s https://api.ipify.org)


echo "====== 写入配置文件 ======"

cat > /usr/local/etc/xray/config.json <<EOF
{
"log": {
"loglevel": "warning"
},
"inbounds": [
{
"tag": "dokodemo-in",
"port": 443,
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
"id": "$UUID",
"flow": "xtls-rprx-vision"
}
],
"decryption": "none"
},
"streamSettings": {
"network": "tcp",
"security": "reality",
"realitySettings": {
"dest": "speed.cloudflare.com:443",
"serverNames": [
"speed.cloudflare.com"
],
"privateKey": "$PRIVATE_KEY",
"shortIds": [
"",
"$SHORT_ID"
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
"speed.cloudflare.com"
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


echo "====== 启动 Xray ======"

systemctl daemon-reload
systemctl enable xray
systemctl restart xray


echo
echo "===== Reality 节点 ====="
echo
echo "地址: $IP"
echo "端口: 443"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "SNI: speed.cloudflare.com"
echo "Flow: xtls-rprx-vision"
echo
echo "分享链接:"
echo
echo "vless://$UUID@$IP:443?encryption=none&security=reality&sni=speed.cloudflare.com&fp=safari&pbk=$PUBLIC_KEY&type=tcp&flow=xtls-rprx-vision#Reality"
echo
