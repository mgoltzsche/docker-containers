#!/bin/sh

IP=$(ip -o -4 addr list eth0 | awk '{print $4}') # IP: xxx.xxx.xxx.xxx/xx
NETWORK=$(ipcalc -ns $IP | sed s/NETWORK=//)
IP_NET=$(echo $NETWORK | sed 's/[^\.]$//')
IP_HOST=$(echo $NETWORK | sed 's/.*\.//')
BRIDGE_IP=$IP_NET$(expr $IP_HOST + 1) # First network host assumed as bridge
RESOLV_CONF_LINE="nameserver $BRIDGE_IP"

# Add bridge IP as nameserver to /etc/resolv.conf
[ $(grep -Fc "$RESOLV_CONF_LINE" /etc/resolv.conf) -ne 0 ] || echo "$RESOLV_CONF_LINE" >> /etc/resolv.conf

#$(ipcalc -ns $IP | sed s/NETWORK=// | sed 's/[^\.]$//')$(ipcalc -ns $IP | sed s/NETWORK=// | sed 's/.*\.//')
