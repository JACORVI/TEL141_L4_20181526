#!/bin/bash
# no_internet_to_network.sh
# Elimina las reglas de Iptables que realizan el masquerading (y el forward
# asociado) del trafico de una VLAN determinada, agregadas por
# internet_to_network.sh.
#
# Parametros de entrada:
#   $1 : VLAN ID
#   $2 : Direccion de red a utilizar, en formato CIDR (ej. 192.168.0.0/24)
#   $3 : (opcional) Interfaz de salida a Internet. Por defecto: ens3
#
# Uso:
#   ./no_internet_to_network.sh 100 192.168.0.0/24
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./no_internet_to_network.sh "100" "192.168.0.0/24"

set -uo pipefail

if [[ $# -lt 2 ]]; then
    echo "Uso: $0 <vlan_id> <cidr> [interfaz_salida]" >&2
    exit 1
fi

VLAN_ID=$1
CIDR=$2
EXT_IFACE=${3:-ens3}

echo "[no_internet_to_network] Deshabilitando salida a Internet para VLAN $VLAN_ID ($CIDR)..."

iptables -t nat -D POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -s "$CIDR" -o "$EXT_IFACE" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d "$CIDR" -i "$EXT_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

echo "[no_internet_to_network] Reglas eliminadas (si existian)."
