#!/bin/bash
set -e

#=============== 彩色输出函数 ===============
green()  { echo -e "\033[32m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

#=============== 安装依赖 ===============
install_dependencies() {
  apt update -y >/dev/null 2>&1
  apt install -y curl wget xz-utils jq xxd resolvconf gnupg lsb-release wireguard wireguard-tools >/dev/null 2>&1
}

#=============== 获取公网 IP ===============
get_ip() {
  curl -s ipv4.ip.sb || curl -s ifconfig.me
}

#=============== 安装 Xray ===============
install_xray() {
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
}

#=============== 生成 Reality 密钥 ===============
gen_keys() {
  XRAY_BIN=$(command -v xray || echo "/usr/local/bin/xray")
  KEYS=$($XRAY_BIN x25519)
  PRIV_KEY=$(echo "$KEYS" | awk '/Private/ {print $3}')
  PUB_KEY=$(echo "$KEYS" | awk '/Public/ {print $3}')
  SHORT_ID=$(head -c 4 /dev/urandom | xxd -p)
}

#=============== 安装并配置 VLESS Reality ===============
install_vless_reality() {
  read -rp "监听端口（默认443）: " PORT
  read -rp "节点备注: " REMARK
  UUID=$(cat /proc/sys/kernel/random/uuid)
  SNI="www.cloudflare.com"
  gen_keys
  mkdir -p /usr/local/etc/xray
  cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "email": "$REMARK" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$SNI:443",
        "xver": 0,
        "serverNames": ["$SNI"],
        "privateKey": "$PRIV_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
  systemctl daemon-reexec
  systemctl restart xray
  systemctl enable xray
  IP=$(get_ip)
  LINK="vless://$UUID@$IP:$PORT?type=tcp&security=reality&sni=$SNI&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID#$REMARK"
  green "✅ VLESS Reality链接："
  echo "$LINK"
}

#=============== 安装并配置 Trojan Reality ===============
install_trojan_reality() {
  read -rp "监听端口（默认8443）: " PORT
  read -rp "密码: " PASSWORD
  read -rp "节点备注: " REMARK
  SNI="www.cloudflare.com"
  gen_keys
  mkdir -p /usr/local/etc/xray
  cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "trojan",
    "settings": {
      "clients": [{ "password": "$PASSWORD" }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$SNI:443",
        "xver": 0,
        "serverNames": ["$SNI"],
        "privateKey": "$PRIV_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
  systemctl daemon-reexec
  systemctl restart xray
  systemctl enable xray
  IP=$(get_ip)
  LINK="trojan://$PASSWORD@$IP:$PORT?security=reality&sni=$SNI&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID#$REMARK"
  green "✅ Trojan Reality链接："
  echo "$LINK"
}

#=============== 安装并配置 CF Warp ===============
install_warp() {
  if ! command -v warp-cli >/dev/null; then
    curl -s https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor > /etc/apt/keyrings/cloudflare-warp.gpg
    echo "deb [signed-by=/etc/apt/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list
    apt update >/dev/null 2>&1
    apt install -y cloudflare-warp >/dev/null 2>&1
  fi

  warp-cli --accept-tos register >/dev/null 2>&1
  warp-cli set-mode warp >/dev/null 2>&1
  warp-cli connect >/dev/null 2>&1
  sleep 2

  # 检查是否成功连接
  STATUS=$(warp-cli status 2>/dev/null | grep "Connection status" | awk '{print $3}')
  if [ "$STATUS" = "Connected" ]; then
    green "✅ Warp 已连接成功"
  else
    red "❌ Warp 连接失败，请检查"
  fi
}

#=============== 主菜单 ===============
main_menu() {
  while true; do
    clear
    green "========= VLESS & Trojan Reality 一键脚本 V4.0 ========="
    echo "1. 安装 VLESS Reality"
    echo "2. 安装 Trojan Reality"
    echo "3. 安装 CF Warp 并配置 VLESS 出站"
    echo "4. 安装 CF Warp 并配置 Trojan 出站"
    echo "0. 退出"
    read -rp "请选择操作: " choice
    case $choice in
      1) install_xray; install_vless_reality ;;
      2) install_xray; install_trojan_reality ;;
      3) install_warp; install_xray; install_vless_reality ;;
      4) install_warp; install_xray; install_trojan_reality ;;
      0) exit 0 ;;
      *) red "❌ 请输入正确选项" ; sleep 1 ;;
    esac
  done
}

install_dependencies
main_menu