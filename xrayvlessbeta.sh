#!/bin/bash
set -e
#====== 彩色输出函数 (必须放前面) ======
green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

#====== 检测系统类型 ======
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  else
    OS=$(uname -s)
  fi
  echo "$OS"
}

install_dependencies() {
  OS=$(detect_os)
  green "检测到系统: $OS，安装依赖..."
  case "$OS" in
    ubuntu|debian)
      sudo apt update
      sudo apt install -y curl wget xz-utils jq xxd >/dev/null 2>&1
      ;;
    centos|rhel|rocky|alma)
      sudo yum install -y epel-release
      sudo yum install -y curl wget xz jq vim-common >/dev/null 2>&1
      ;;
    alpine)
      sudo apk update
      sudo apk add --no-cache curl wget xz jq vim
      ;;
    *)
      red "不支持的系统: $OS"
      exit 1
      ;;
  esac
}

check_and_install_xray() {
  if command -v xray >/dev/null 2>&1; then
    green "✅ Xray 已安装，跳过安装"
  else
    green "❗检测到 Xray 未安装，正在安装..."
    bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    XRAY_BIN=$(command -v xray || echo "/usr/local/bin/xray")
    if [ ! -x "$XRAY_BIN" ]; then
      red "❌ Xray 安装失败，请检查"
      exit 1
    fi
    green "✅ Xray 安装完成"
  fi
}

restart_xray_service() {
  OS=$(detect_os)
  if command -v systemctl >/dev/null 2>&1; then
    green "用 systemd 重启 xray"
    sudo systemctl daemon-reexec
    sudo systemctl restart xray
    sudo systemctl enable xray
  elif command -v rc-service >/dev/null 2>&1; then
    green "用 OpenRC 重启 xray"
    sudo rc-service xray restart
    sudo rc-update add xray default
  else
    yellow "⚠️ 找不到合适的服务管理命令，请手动启动 xray"
  fi
}

stop_xray_service() {
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop xray
    sudo systemctl disable xray
  elif command -v rc-service >/dev/null 2>&1; then
    sudo rc-service xray stop
    sudo rc-update del xray default
  else
    yellow "⚠️ 找不到合适的服务管理命令，请手动停止 xray"
  fi
}

# 以下保持你原有函数不变，省略部分内容，只写重点函数示例
# 流媒体解锁检测
check_streaming_unlock() {
  green "==== 流媒体解锁检测 ===="
  test_site() {
    local name=$1 url=$2 keyword=$3
    echo -n "检测 $name ... "
    html=$(curl -s --max-time 10 -A "Mozilla/5.0" "$url")
    if echo "$html" | grep -qi "$keyword"; then
      echo "✅ 解锁"
    else
      echo "❌ 未解锁"
    fi
  }
  test_site "Netflix" "https://www.netflix.com/title/80018499" "netflix"
  test_site "Disney+" "https://www.disneyplus.com/" "disney"
  test_site "YouTube Premium" "https://www.youtube.com/premium" "Premium"
  test_site "ChatGPT" "https://chat.openai.com/" "OpenAI"
  test_site "Twitch" "https://www.twitch.tv/" "Twitch"
  test_site "HBO Max" "https://play.hbomax.com/" "HBO"
  echo "=========================="
  read -rp "按任意键返回菜单..."
}

# IP 纯净度检测
check_ip_clean() {
  echo "==== IP 纯净度检测 ===="
  IP=$(curl -s https://api.ipify.org)
  echo "本机公网 IP：$IP"
  hosts=("openai.com" "api.openai.com" "youtube.com" "tiktok.com" "twitter.com" "wikipedia.org")
  for h in "${hosts[@]}"; do
    echo -n "测试 $h ... "
    if timeout 5 curl -sI https://$h >/dev/null; then
      echo "✅"
    else
      echo "❌"
    fi
  done
  echo "========================"
  read -rp "按任意键返回菜单..."
}

# 你原有的安装VLESS/ Trojan等函数保持不变，只需要改重启服务调用改为新函数
install_trojan_reality() {
  check_and_install_xray
  XRAY_BIN=$(command -v xray || echo "/usr/local/bin/xray")
  read -rp "监听端口（如 443）: " PORT
  read -rp "节点备注（如：trojanNode）: " REMARK

  PASSWORD=$(openssl rand -hex 8)
  KEYS=$($XRAY_BIN x25519)
  PRIV_KEY=$(echo "$KEYS" | awk '/Private/ {print $3}')
  PUB_KEY=$(echo "$KEYS" | awk '/Public/ {print $3}')
  SHORT_ID=$(head -c 4 /dev/urandom | xxd -p)
  SNI="www.cloudflare.com"

  mkdir -p /usr/local/etc/xray
  cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "trojan",
    "settings": {
      "clients": [{ "password": "$PASSWORD", "email": "$REMARK" }]
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

  restart_xray_service

  IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)
  LINK="trojan://$PASSWORD@$IP:$PORT#$REMARK"
  green "✅ Trojan Reality 节点链接如下："
  echo "$LINK"
  read -rp "按任意键返回菜单..."
}

# 主菜单逻辑，保持不变，调用 install_dependencies 等新函数
while true; do
  clear
  green "AD：优秀流媒体便宜小鸡：sadidc.cn"
  green "AD：拼好机：gelxc.cloud"
  green "======= VLESS Reality 一键脚本V4.1beta（多系统支持） ======="
  echo "1) 安装并配置 VLESS Reality 节点"
  echo "2) 生成 Trojan Reality 节点"
  echo "3) 生成 VLESS 中转链接"
  echo "4) 开启 BBR 加速"
  echo "5) 测试流媒体解锁"
  echo "6) 检查 IP 纯净度"
  echo "7) Ookla Speedtest 测试"
  echo "8) 卸载 Xray"
  echo "9) 查询 Xray 已部署协议"
  echo "0) 退出"
  echo
  read -rp "请选择操作: " choice

  case "$choice" in
    1)
      install_dependencies
      check_and_install_xray
      XRAY_BIN=$(command -v xray || echo "/usr/local/bin/xray")
      read -rp "监听端口（如 443）: " PORT
      read -rp "节点备注: " REMARK
      UUID=$(cat /proc/sys/kernel/random/uuid)
      KEYS=$($XRAY_BIN x25519)
      PRIV_KEY=$(echo "$KEYS" | awk '/Private/ {print $3}')
      PUB_KEY=$(echo "$KEYS" | awk '/Public/ {print $3}')
      SHORT_ID=$(head -c 4 /dev/urandom | xxd -p)
      SNI="www.cloudflare.com"

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

      restart_xray_service

      IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)
      LINK="vless://$UUID@$IP:$PORT?type=tcp&security=reality&sni=$SNI&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID#$REMARK"
      green "✅ 节点链接如下："
      echo "$LINK"
      read -rp "按任意键返回菜单..."
      ;;
    2)
      install_dependencies
      install_trojan_reality
      ;;
    3)
      read -rp "请输入原始 VLESS 链接: " old_link
      read -rp "请输入中转服务器地址（IP 或域名）: " new_server
      new_link=$(echo "$old_link" | sed -E "s#(@)[^:]+#\\1$new_server#")
      green "🎯 生成的新中转链接："
      echo "$new_link"
      read -rp "按任意键返回菜单..."
      ;;
    4)
      echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
      echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
      sudo sysctl -p
      green "✅ BBR 加速已启用"
      read -rp "按任意键返回菜单..."
      ;;
    5)
      check_streaming_unlock
      ;;
    6)
      check_ip_clean
      ;;
    7)
      wget -q https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz
      tar -zxf ookla-speedtest-1.2.0-linux-x86_64.tgz
      chmod +x speedtest
      ./speedtest --accept-license --accept-gdpr
      rm -f speedtest speedtest.5 speedtest.md ookla-speedtest-1.2.0-linux-x86_64.tgz
      read -rp "按任意键返回菜单..."
      ;;
    8)
      stop_xray_service
      sudo rm -rf /usr/local/etc/xray /usr/local/bin/xray
      green "✅ Xray 已卸载"
      read -rp "按任意键返回菜单..."
      ;;
    9)
      # 你之前的 show_deployed_protocols 函数这里调用
      show_deployed_protocols
      ;;
    0)
      exit 0
      ;;
    *)
      red "❌ 无效选项，请重试"
      sleep 1
      ;;
  esac
done