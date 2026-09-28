#!/bin/bash
# no_routing_networks.sh
# Elimina las reglas de Iptables que enrutan el trafico entre dos VLANs,
# agregadas por routing_networks.sh.
#
# Parametros de entrada:
#   $1 : VLAN ID 1
#   $2 : VLAN ID 2
#
# Uso:
#   ./no_routing_networks.sh 100 200
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./no_routing_networks.sh "100" "200"

set -uo pipefail

if [[ $# -lt 2 ]]; then
    echo "Uso: $0 <vlan_id_1> <vlan_id_2>" >&2
    exit 1
fi

GW1="gw_vlan$1"
GW2="gw_vlan$2"

echo "[no_routing_networks] Deshabilitando enrutamiento entre VLAN $1 y VLAN $2..."

iptables -D FORWARD -i "$GW1" -o "$GW2" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$GW2" -o "$GW1" -j ACCEPT 2>/dev/null || true

echo "[no_routing_networks] Reglas eliminadas (si existian)."
