#!/bin/bash
###########################################################################
#          ::::::::       :::    :::       ::::::::       ::::::::   ::::::::::: 
#        :+:    :+:      :+:    :+:      :+:    :+:     :+:    :+:      :+:      
#       +:+             +:+    +:+      +:+    +:+     +:+             +:+       
#      :#:             +#++:++#++      +#+    +:+     +#++:++#++      +#+        
#     +#+   +#+#      +#+    +#+      +#+    +#+            +#+      +#+         
#    #+#    #+#      #+#    #+#      #+#    #+#     #+#    #+#      #+#          
#    ########       ###    ###       ########       ########       ###           
#                           ROARING FOR PRIVACY                          
###########################################################################

# Anonymity Guard - Tor transparent proxy + MAC rotation + DNS isolation
# Enhanced version with interactive setup and safer flow
###########################################################################

if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root."
  exit 1
fi

LOG_FILE="/var/log/anonymity-guard.log"
TOR_USER="debian-tor"
INTERVAL=""
INTERFACE=""

log() { echo "[$(date +"%F %T")] $1" | tee -a "$LOG_FILE"; }

# ------------------------------ INTERACTIVE SETUP ------------------------------

ask_user_settings() {
  echo ""
  echo "=== Anonymity Guard Setup ==="

  if [ -z "$INTERVAL" ]; then
    read -p "Enter rotation interval in seconds (default 300): " INTERVAL
    INTERVAL="${INTERVAL:-300}"
  fi

  if [ -z "$INTERFACE" ]; then
    echo ""
    echo "Detected interfaces:"
    ip -o link show | awk -F': ' '/^[0-9]+: / {print $2}'
    echo ""

    read -p "Enter interface to rotate (leave blank for auto-detect): " INTERFACE
  fi

  echo ""
  log "Using INTERVAL=$INTERVAL seconds, INTERFACE=${INTERFACE:-auto}"
}

# Safe interface detection
get_interfaces() {
  ip -o link show | awk -F': ' '/^[0-9]+: / {print $2}' \
    | grep -vE 'lo|docker|veth|virbr|br-|tun|tap'
}

# ------------------------------ STOP MODE -------------------------------------

if [[ "$1" == "--stop" ]]; then
  log "Stopping Anonymity Guard..."

  iptables -F
  iptables -t nat -F
  iptables -P OUTPUT ACCEPT
  iptables -P FORWARD ACCEPT

  for iface in $(get_interfaces); do
    ip link set "$iface" down
    macchanger -p "$iface" >/dev/null 2>&1
    ip link set "$iface" up
  done

  chattr -i /etc/resolv.conf
  echo "nameserver 8.8.8.8" > /etc/resolv.conf

  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null

  systemctl stop tor

  log "Reverted changes. Exiting."
  exit 0
fi

# ------------------------------ PARSE FLAGS ------------------------------------

while [[ $# -gt 0 ]]; do
  case $1 in
    --interval) INTERVAL="$2"; shift 2 ;;
    --interface) INTERFACE="$2"; shift 2 ;;
    --log) cat "$LOG_FILE"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

ask_user_settings

# ------------------------------ INSTALL DEPS -----------------------------------

log "Installing required packages..."
apt update -y >> "$LOG_FILE" 2>&1
apt install -y tor macchanger netcat-traditional iptables-persistent >> "$LOG_FILE" 2>&1

# ------------------------------ CONFIGURE TOR ----------------------------------

log "Configuring Tor..."

add_tor_conf() {
  grep -q "^$1" /etc/tor/torrc || echo "$1" >> /etc/tor/torrc
}

add_tor_conf "ControlPort 9051"
add_tor_conf "CookieAuthentication 0"
add_tor_conf "AutomapHostsOnResolve 1"
add_tor_conf "VirtualAddrNetworkIPv4 10.192.0.0/10"
add_tor_conf "DNSPort 5353"
add_tor_conf "TransPort 9040"

systemctl restart tor

# ------------------------------ SYSTEM HARDENING --------------------------------

log "Disabling IPv6..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
grep -q disable_ipv6 /etc/sysctl.conf || cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

log "Locking DNS..."
chattr -i /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf

# ------------------------------ HOSTNAME RANDOMIZATION --------------------------

NEW_HOSTNAME="kali-$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)"
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/^127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts
log "New hostname: $NEW_HOSTNAME"

# ------------------------------ IPTABLES STRICT MODE ----------------------------

TOR_UID=$(id -u $TOR_USER)

log "Applying iptables rules..."

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

log "Anonymity Guard started."

# ------------------------------ MAIN LOOP --------------------------------------

while true; do
  
  if ! pgrep -x tor >/dev/null; then
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    log "[CRITICAL] Tor failure! Network locked down."
    exit 1
  fi

  printf "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" \
    | nc 127.0.0.1 9051 >/dev/null 2>&1

  log "Tor circut rotated (NEWNYM)."

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

  log "MAC rotation complete."

  sleep "$INTERVAL"
done
