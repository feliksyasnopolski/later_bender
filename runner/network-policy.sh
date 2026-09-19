#!/usr/bin/env bash
set -euo pipefail

NETWORK_NAME=${WORKSPACE_DOCKER_NETWORK:-later-bender-workspaces}
NETWORK_SUBNET=${WORKSPACE_DOCKER_SUBNET:-172.30.0.0/16}
NETWORK_GATEWAY=${WORKSPACE_DOCKER_GATEWAY:-172.30.0.1}

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create --driver bridge --subnet "$NETWORK_SUBNET" --gateway "$NETWORK_GATEWAY" --ipv6=false "$NETWORK_NAME" >/dev/null
fi

bridge=br-$(docker network inspect -f '{{.Id}}' "$NETWORK_NAME" | cut -c1-12)

iptables -N LB_WS_EGRESS 2>/dev/null || true
iptables -C DOCKER-USER -j LB_WS_EGRESS 2>/dev/null || iptables -I DOCKER-USER 1 -j LB_WS_EGRESS
iptables -C LB_WS_EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A LB_WS_EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
for cidr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
  iptables -C LB_WS_EGRESS -s "$NETWORK_SUBNET" -d "$cidr" -j DROP 2>/dev/null || iptables -A LB_WS_EGRESS -s "$NETWORK_SUBNET" -d "$cidr" -j DROP
done
iptables -C LB_WS_EGRESS -s "$NETWORK_SUBNET" -j ACCEPT 2>/dev/null || iptables -A LB_WS_EGRESS -s "$NETWORK_SUBNET" -j ACCEPT
iptables -C LB_WS_EGRESS -j RETURN 2>/dev/null || iptables -A LB_WS_EGRESS -j RETURN
iptables -C INPUT -i "$bridge" -s "$NETWORK_SUBNET" -j DROP 2>/dev/null || iptables -I INPUT 1 -i "$bridge" -s "$NETWORK_SUBNET" -j DROP
echo "$NETWORK_NAME $bridge $NETWORK_SUBNET"
