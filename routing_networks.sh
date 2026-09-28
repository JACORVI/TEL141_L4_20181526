#!/bin/bash
# routing_networks.sh
# Anade las reglas de Iptables que enrutan el trafico entre dos VLANs,
# permitiendo el forward bidireccional entre sus interfaces gateway
# (gw_vlan<ID>, creadas por create_network_vlan.sh).
#
# Parametros de entrada:
#   $1 : VLAN ID 1
#   $2 : VLAN ID 2
#
# Uso:
#   ./routing_networks.sh 100 200
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./routing_networks.sh "100" "200"

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Uso: $0 <vlan_id_1> <vlan_id_2>" >&2
    exit 1
fi

GW1="gw_vlan$1"
GW2="gw_vlan$2"

rule_exists() {
    iptables -C "$@" 2>/dev/null
}

echo "[routing_networks] Habilitando enrutamiento entre VLAN $1 y VLAN $2..."

if ! rule_exists FORWARD -i "$GW1" -o "$GW2" -j ACCEPT; then
    iptables -A FORWARD -i "$GW1" -o "$GW2" -j ACCEPT
fi

if ! rule_exists FORWARD -i "$GW2" -o "$GW1" -j ACCEPT; then
    iptables -A FORWARD -i "$GW2" -o "$GW1" -j ACCEPT
fi

echo "[routing_networks] Reglas aplicadas correctamente."
