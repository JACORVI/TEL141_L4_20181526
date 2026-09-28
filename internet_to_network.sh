#!/bin/bash
# internet_to_network.sh
# Anade las reglas de Iptables que permiten la salida a Internet (masquerading)
# del trafico de una VLAN determinada.
#
# Parametros de entrada:
#   $1 : VLAN ID
#   $2 : Direccion de red a utilizar, en formato CIDR (ej. 192.168.0.0/24)
#   $3 : (opcional) Interfaz de salida a Internet. Por defecto: ens3
#        (interfaz del Server 3 hacia Internet, segun topologia del curso)
#
# Uso:
#   ./internet_to_network.sh 100 192.168.0.0/24
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./internet_to_network.sh "100" "192.168.0.0/24"

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Uso: $0 <vlan_id> <cidr> [interfaz_salida]" >&2
    exit 1
fi

VLAN_ID=$1
CIDR=$2
EXT_IFACE=${3:-ens3}

rule_exists() {
    # $1 = tabla (opcional, "" para filter), resto = especificacion de la regla
    local table=$1; shift
    if [[ -n "$table" ]]; then
        iptables -t "$table" -C "$@" 2>/dev/null
    else
        iptables -C "$@" 2>/dev/null
    fi
}

echo "[internet_to_network] Habilitando salida a Internet para VLAN $VLAN_ID ($CIDR) via $EXT_IFACE..."

if ! rule_exists nat POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE; then
    iptables -t nat -A POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE
fi

if ! rule_exists "" FORWARD -s "$CIDR" -o "$EXT_IFACE" -j ACCEPT; then
    iptables -A FORWARD -s "$CIDR" -o "$EXT_IFACE" -j ACCEPT
fi

if ! rule_exists "" FORWARD -d "$CIDR" -i "$EXT_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT; then
    iptables -A FORWARD -d "$CIDR" -i "$EXT_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT
fi

echo "[internet_to_network] Reglas aplicadas correctamente."
