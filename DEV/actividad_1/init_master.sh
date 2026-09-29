#!/bin/bash
# init_master.sh
# Inicializa el nodo MASTER (Head Node) del cluster:
#   1. Crea el OVS local 'br-int' si no existiera.
#   2. Conecta al bridge las interfaces provistas como parametros.
#   3. Activa IPv4 forwarding.
#   4. Cambia la politica por defecto de la cadena FORWARD (tabla filter) a DROP.
#
# Parametros de entrada:
#   $1..$N : Interfaces de red a conectar al OVS 'br-int'
#
# Uso:
#   ./init_master.sh ens4 ens5
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./init_master.sh "ens4" "ens5"

set -euo pipefail

BRIDGE="br-int"

if [[ $# -lt 1 ]]; then
    echo "Uso: $0 <interfaz1> [interfaz2 ...]" >&2
    exit 1
fi

# 1. Crear el bridge OVS 'br-int' si no existe
if ! ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    echo "[init_master] Creando bridge OVS '$BRIDGE'..."
    ovs-vsctl add-br "$BRIDGE"
else
    echo "[init_master] El bridge '$BRIDGE' ya existe, se omite creacion."
fi

# 2. Conectar las interfaces provistas al bridge
for iface in "$@"; do
    if ovs-vsctl list-ports "$BRIDGE" | grep -qx "$iface"; then
        echo "[init_master] La interfaz '$iface' ya esta conectada a '$BRIDGE'."
    else
        echo "[init_master] Conectando interfaz '$iface' a '$BRIDGE'..."
        ovs-vsctl add-port "$BRIDGE" "$iface"
    fi
done

# 3. Activar IPv4 forwarding (en caliente y de forma persistente)
echo "[init_master] Activando IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# 4. Cambiar la politica por defecto de FORWARD de ACCEPT a DROP
echo "[init_master] Cambiando politica por defecto de la cadena FORWARD a DROP..."
iptables -P FORWARD DROP

echo "[init_master] Nodo master inicializado correctamente."
