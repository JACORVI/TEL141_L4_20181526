#!/bin/bash
# create_network_vlan.sh
# Crea una red aislada (VLAN) sobre el OVS 'br-int':
#   1. Crea una interfaz interna en el OVS con el VLAN ID definido y le
#      asigna la primera direccion de la red (funciona como gateway).
#   2. Si DHCP esta habilitado, crea un Linux Network Namespace que aloja
#      el servicio DHCP (dnsmasq), usando la segunda direccion de la red,
#      y anuncia como gateway la interfaz creada en el paso anterior.
#
# Parametros de entrada:
#   $1 : VLAN ID
#   $2 : Direccion de red a utilizar, en formato CIDR (ej. 192.168.0.0/24)
#   $3 : DHCP habilitado ("yes"/"no")
#   $4 : Rango de direcciones para DHCP, formato "inicio,fin"
#        (solo requerido si $3 = "yes", ej. 192.168.0.10,192.168.0.100)
#
# Uso:
#   ./create_network_vlan.sh 100 192.168.0.0/24 yes 192.168.0.10,192.168.0.100
#   ./create_network_vlan.sh 200 192.168.2.0/24 no
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./create_network_vlan.sh "100" "192.168.0.0/24" "yes" "192.168.0.10,192.168.0.100"

set -euo pipefail

BRIDGE="br-int"

if [[ $# -lt 3 ]]; then
    echo "Uso: $0 <vlan_id> <cidr> <dhcp:yes|no> [rango_inicio,rango_fin]" >&2
    exit 1
fi

VLAN_ID=$1
CIDR=$2
DHCP_ENABLED=$3
DHCP_RANGE=${4:-}

PREFIX="${CIDR#*/}"
GW_PORT="gw_vlan${VLAN_ID}"
DHCP_PORT="dhcp_vlan${VLAN_ID}"
DHCP_NS="dhcp_vlan${VLAN_ID}"

# --- Funciones auxiliares de aritmetica IPv4 (sin dependencias externas) ---
ip_to_int() {
    local a b c d
    IFS='.' read -r a b c d <<< "$1"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ip() {
    local ip=$1
    echo "$(( (ip >> 24) & 255 )).$(( (ip >> 16) & 255 )).$(( (ip >> 8) & 255 )).$(( ip & 255 ))"
}

ip_from_cidr_offset() {
    local cidr=$1 offset=$2
    local net_ip=${cidr%/*}
    local net_int
    net_int=$(ip_to_int "$net_ip")
    int_to_ip $(( net_int + offset ))
}

GATEWAY_IP=$(ip_from_cidr_offset "$CIDR" 1)

# 1. Crear la interfaz interna (gateway) en el OVS, con el VLAN ID definido
if ovs-vsctl list-ports "$BRIDGE" | grep -qx "$GW_PORT"; then
    echo "[create_network_vlan] El puerto '$GW_PORT' ya existe, se omite creacion."
else
    echo "[create_network_vlan] Creando puerto gateway '$GW_PORT' (VLAN $VLAN_ID)..."
    ovs-vsctl add-port "$BRIDGE" "$GW_PORT" tag="$VLAN_ID" -- set interface "$GW_PORT" type=internal
fi

if ! ip addr show "$GW_PORT" | grep -q "$GATEWAY_IP/$PREFIX"; then
    ip addr add "$GATEWAY_IP/$PREFIX" dev "$GW_PORT"
fi
ip link set dev "$GW_PORT" up

echo "[create_network_vlan] Gateway de la VLAN $VLAN_ID: $GATEWAY_IP/$PREFIX"

# 2. Si DHCP esta habilitado, crear el namespace y levantar dnsmasq
if [[ "$DHCP_ENABLED" == "yes" ]]; then
    if [[ -z "$DHCP_RANGE" ]]; then
        echo "[create_network_vlan] ERROR: se requiere el rango DHCP (\"inicio,fin\")." >&2
        exit 1
    fi

    DHCP_START="${DHCP_RANGE%%,*}"
    DHCP_END="${DHCP_RANGE##*,}"
    DHCP_IP=$(ip_from_cidr_offset "$CIDR" 2)

    if ! ip netns list | grep -qx "$DHCP_NS"; then
        echo "[create_network_vlan] Creando network namespace '$DHCP_NS'..."
        ip netns add "$DHCP_NS"
    fi

    if ! ovs-vsctl list-ports "$BRIDGE" | grep -qx "$DHCP_PORT"; then
        echo "[create_network_vlan] Creando puerto DHCP '$DHCP_PORT' (VLAN $VLAN_ID)..."
        ovs-vsctl add-port "$BRIDGE" "$DHCP_PORT" tag="$VLAN_ID" -- set interface "$DHCP_PORT" type=internal
        ip link set "$DHCP_PORT" netns "$DHCP_NS"
    fi

    ip netns exec "$DHCP_NS" ip addr add "$DHCP_IP/$PREFIX" dev "$DHCP_PORT" 2>/dev/null || true
    ip netns exec "$DHCP_NS" ip link set dev "$DHCP_PORT" up
    ip netns exec "$DHCP_NS" ip link set dev lo up

    PID_FILE="/var/run/dnsmasq_vlan${VLAN_ID}.pid"
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "[create_network_vlan] dnsmasq ya esta corriendo para la VLAN $VLAN_ID."
    else
        echo "[create_network_vlan] Levantando dnsmasq en '$DHCP_NS' (rango $DHCP_START - $DHCP_END)..."
        ip netns exec "$DHCP_NS" dnsmasq \
            --interface="$DHCP_PORT" \
            --bind-interfaces \
            --except-interface=lo \
            --dhcp-range="${DHCP_START},${DHCP_END},12h" \
            --dhcp-option=3,"$GATEWAY_IP" \
            --pid-file="$PID_FILE"
    fi

    echo "[create_network_vlan] DHCP habilitado en $DHCP_IP/$PREFIX (namespace $DHCP_NS)."
else
    echo "[create_network_vlan] DHCP deshabilitado para la VLAN $VLAN_ID."
fi

echo "[create_network_vlan] Red VLAN $VLAN_ID ($CIDR) creada correctamente."
