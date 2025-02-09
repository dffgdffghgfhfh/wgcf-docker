#!/usr/bin/env bash

set -e

_downwgcf() {
  echo
  echo "clean up"
  if ! wg-quick down wgcf; then
    echo "error down"
  fi
  echo "clean up done"
  exit 0
}

runwgcf() {
  trap '_downwgcf' ERR TERM INT

  _enableV4="1"
  if [ "$1" = "-6" ]; then
    _enableV4=""
  fi

  # 检查并生成必要的文件
  if [ ! -e "wgcf-account.toml" ]; then
    echo "Registering account..."
    wgcf register --accept-tos
    sleep 10  # 增加延时避免请求过多
  fi

  if [ ! -e "wgcf-profile.conf" ]; then
    echo "Generating profile..."
    wgcf generate
    echo "wgcf-profile.conf generated"
  fi

  # 将配置文件复制到 WireGuard 的目录
  cp wgcf-profile.conf /etc/wireguard/wgcf.conf
  echo "wgcf.conf copied to /etc/wireguard/"

  # 获取默认网关和路由
  DEFAULT_GATEWAY_NETWORK_CARD_NAME=$(route | grep default | awk '{print $8}' | head -1)
  DEFAULT_ROUTE_IP=$(ifconfig $DEFAULT_GATEWAY_NETWORK_CARD_NAME | grep "inet " | awk '{print $2}' | sed "s/addr://")

  echo "Gateway Network Card: ${DEFAULT_GATEWAY_NETWORK_CARD_NAME}"
  echo "Default Route IP: ${DEFAULT_ROUTE_IP}"

  # 修改 WireGuard 配置以适应 IPv4 或 IPv6
  sed -i "/\[Interface\]/a PostDown = ip rule delete from $DEFAULT_ROUTE_IP lookup main" /etc/wireguard/wgcf.conf
  sed -i "/\[Interface\]/a PostUp = ip rule add from $DEFAULT_ROUTE_IP lookup main" /etc/wireguard/wgcf.conf

  if [ "$1" = "-6" ]; then
    sed -i 's/AllowedIPs = 0.0.0.0/#AllowedIPs = 0.0.0.0/' /etc/wireguard/wgcf.conf
  elif [ "$1" = "-4" ]; then
    sed -i 's/AllowedIPs = ::/#AllowedIPs = ::/' /etc/wireguard/wgcf.conf
    sed -i '/^Address = \([0-9a-fA-F]\{1,4\}:\)\{7\}[0-9a-fA-F]\{1,4\}\/[0-9]\{1,3\}/s/^/#/' /etc/wireguard/wgcf.conf
  fi

  # 加载 IP6 规则
  modprobe ip6table_raw
  
  # 启动 WireGuard
  wg-quick up wgcf
  
  # 检查连接状态
  if [ "$_enableV4" ]; then
    _checkV4
  else
    _checkV6
  fi

  echo "OK, wgcf is up."
  
  # 保持容器运行
  sleep infinity & wait
}

_checkV4() {
  echo "Checking network status for IPv4, please wait..."
  while ! curl --max-time 2 ipinfo.io; do
    wg-quick down wgcf
    echo "Sleep 2 and retry again."
    sleep 2
    wg-quick up wgcf
  done
}

_checkV6() {
  echo "Checking network status for IPv6, please wait..."
  while ! curl --max-time 2 -6 ipv6.google.com; do
    wg-quick down wgcf
    echo "Sleep 2 and retry again."
    sleep 2
    wg-quick up wgcf
  done
}

if [ -z "$@" ] || [[ "$1" = -* ]]; then
  runwgcf "$@"
else
  exec "$@"
fi
