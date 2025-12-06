#!/bin/bash

# Anonymity Guard for Kali Linux
# Run as root

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Defaults
INTERVAL=300  # 5 minutes
INTERFACE=""
LOG_FILE="/var/log/anonymity-guard.log"
TOR_USER="debian-tor"

# Safe interface detection (skip lo and virtuals)
get_interfaces() {
  ip -o link show | awk -F': ' '/^[0-9]+: / {print $2}' \
  | grep -vE 'lo|docker|veth|virbr|br-|tun|tap'
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --interface)
      INTERFACE="$2"
      shift 2
      ;;
    --stop)
      echo "Stopping Anonymity Guard..." | tee -a "$LOG_FILE"

      iptables -F
      iptables -t nat -F
      iptables -P OUTPUT ACCEPT
      iptables -P FORWARD ACCEPT
      netfilter-persistent save

      for iface in $(get_interfaces); do
        ip link set "$iface" down
        macchanger -p "$iface"
        ip link set "$iface" up
      done

      sysctl -w net.ipv6.conf.all.disable_ipv6=0
      sysctl -w net.ipv6.conf.default.disable_ipv6=0
      sed -i '/disable_ipv6/d' /etc/sysctl.conf
      sysctl -p

      chattr -i /etc/resolv.conf
      echo "nameserver 8.8.8.8" > /etc/resolv.conf

      systemctl stop tor

      echo "Reverted changes." | tee -a "$LOG_FILE"
      exit 0
      ;;
    --log)
      cat "$LOG_FILE"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Install dependencies (safe)
apt update -y >> "$LOG_FILE" 2>&1
apt install -y tor macchanger net-tools netcat-traditional iptables-persistent >> "$LOG_FILE" 2>&1

# Configure Tor (idempotent)
add_tor_conf() {
  grep -q "^$1" /etc/tor/torrc || echo "$1" >> /etc/tor/torrc
}

add_tor_conf "ControlPort 9051"
add_tor_conf "CookieAuthentication 0"
add_tor_conf "VirtualAddrNetworkIPv4 10.192.0.0/10"
add_tor_conf "AutomapHostsOnResolve 1"
add_tor_conf "TransPort 9040"
add_tor_conf "DNSPort 5353"

systemctl restart tor >> "$LOG_FILE" 2>&1

# Disable IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
grep -q disable_ipv6 /etc/sysctl.conf || cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p

# DNS
chattr -i /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf

# Random hostname
NEW_HOSTNAME="kali-$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/^127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts

# iptables
TOR_UID="$(id -u $TOR_USER)"

iptables -F
iptables -t nat -F

iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports 9040
iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN

iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -j REJECT

netfilter-persistent save

echo "Anonymity Guard started. Interval = $INTERVAL sec" | tee -a "$LOG_FILE"

# Loop
while true; do
  if ! pgrep -x tor >/dev/null; then
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    echo "Tor failed! Network locked down." | tee -a "$LOG_FILE"
    exit 1
  fi

  # NEWNYM
  printf "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051 >> "$LOG_FILE" 2>&1
  echo "Tor identity rotated." | tee -a "$LOG_FILE"

  # MAC rotation
  if [ -n "$INTERFACE" ]; then
    IFACES="$INTERFACE"
  else
    IFACES=$(get_interfaces)
  fi

  for iface in $IFACES; do
    ip link set "$iface" down
    macchanger -r "$iface" >> "$LOG_FILE" 2>&1
    ip link set "$iface" up
  done

  echo "MAC addresses rotated." | tee -a "$LOG_FILE"

  sleep "$INTERVAL"
done
