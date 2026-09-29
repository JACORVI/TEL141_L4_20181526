#!/bin/bash
# init_worker.sh
# Inicializa un nodo WORKER (Compute) del cluster:
#   1. Crea el OVS local 'br-int' si no existiera.
#   2. Conecta al bridge las interfaces provistas como parametros.
#
# A diferencia de init_master.sh, un worker NO modifica IPv4 forwarding
# ni las politicas de iptables, ya que esas tareas son responsabilidad
# exclusiva del nodo master (donde se centraliza el enrutamiento/NAT).
#
# Parametros de entrada:
#   $1..$N : Interfaces de red a conectar al OVS 'br-int'
#
# Uso:
#   ./init_worker.sh ens4
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./init_worker.sh "ens4"

set -euo pipefail

BRIDGE="br-int"

if [[ $# -lt 1 ]]; then
    echo "Uso: $0 <interfaz1> [interfaz2 ...]" >&2
    exit 1
fi

# 1. Crear el bridge OVS 'br-int' si no existe
if ! ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    echo "[init_worker] Creando bridge OVS '$BRIDGE'..."
    ovs-vsctl add-br "$BRIDGE"
else
    echo "[init_worker] El bridge '$BRIDGE' ya existe, se omite creacion."
fi

# 2. Conectar las interfaces provistas al bridge
for iface in "$@"; do
    if ovs-vsctl list-ports "$BRIDGE" | grep -qx "$iface"; then
        echo "[init_worker] La interfaz '$iface' ya esta conectada a '$BRIDGE'."
    else
        echo "[init_worker] Conectando interfaz '$iface' a '$BRIDGE'..."
        ovs-vsctl add-port "$BRIDGE" "$iface"
    fi
done

echo "[init_worker] Nodo worker inicializado correctamente."
