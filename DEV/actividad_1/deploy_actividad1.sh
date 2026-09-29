#!/bin/bash
# deploy_actividad1.sh
# ACTIVIDAD N°1 del Reporte Final (1 pt):
#   "red VLAN sin DHCP y con salida a internet"
#
# Alcance (segun el template real TEL141_LAB4_RF_Template.docx):
#   - Una sola VLAN: VLAN 100 (192.168.0.0/24, gw 192.168.0.1)
#   - SIN servicio DHCP -> direccionamiento ESTATICO
#   - CON salida a Internet
#   - Contenedor en Server 1 (VLAN 100) con IP estatica
#   - VM en Server 2 (VLAN 100) con IP estatica (configurada por VNC)
#
# Se ejecuta DESDE EL SERVER 4 (Cliente), orquestando remotamente via SSH.
#
# Uso: ./deploy_actividad1.sh

set -euo pipefail

SERVER1_IP="10.0.10.1"
SERVER2_IP="10.0.10.2"
SERVER3_IP="10.0.10.3"
SSH_USER="ubuntu"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_remote() {
    local host=$1 script=$2
    shift 2
    echo ">>> [$host] $(basename "$script") $*"
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 \
        "${SSH_USER}@${host}" 'sudo bash -s' "$@" < "$script"
}

echo "=== ACTIVIDAD 1: VLAN 100 sin DHCP y con salida a Internet ==="

# 1. Inicializar nodos (Server 3 = master/gateway, Server 1 y 2 = workers)
run_remote "$SERVER3_IP" "$SCRIPT_DIR/init_master.sh" ens4
run_remote "$SERVER1_IP" "$SCRIPT_DIR/init_worker.sh" ens4
run_remote "$SERVER2_IP" "$SCRIPT_DIR/init_worker.sh" ens4

# 2. Crear la VLAN 100 en Server 3, SIN DHCP (solo se crea el gateway)
run_remote "$SERVER3_IP" "$SCRIPT_DIR/create_network_vlan.sh" 100 192.168.0.0/24 no

# 3. Habilitar salida a Internet para la VLAN 100
run_remote "$SERVER3_IP" "$SCRIPT_DIR/internet_to_network.sh" 100 192.168.0.0/24 ens3

# 4. Desplegar la VM en Server 2 (VLAN 100). Sin DHCP: hay que entrar por
#    VNC (puerto 5901 -> display :1) y asignar manualmente una IP estatica
#    dentro de 192.168.0.0/24 (evitando .1 y el rango reservado), ej:
#      sudo ip addr add 192.168.0.50/24 dev eth0
#      sudo ip route add default via 192.168.0.1
run_remote "$SERVER2_IP" "$SCRIPT_DIR/create_vm.sh" vm_vlan100 br-int 100 5911

# 5. Desplegar el contenedor en Server 1 (VLAN 100) con IP estatica directa
run_remote "$SERVER1_IP" "$SCRIPT_DIR/create_container.sh" cont_vlan100 br-int 100 192.168.0.50/24

cat <<'EOF'

=== Actividad 1 desplegada. Evidencia a capturar para el Reporte Final: ===
  [Server 1 - contenedor]
    sudo ip netns exec cont_vlan100 ip -br addr
    sudo ip netns exec cont_vlan100 arping -c 3 192.168.0.1
    sudo ip netns exec cont_vlan100 ping -c 3 192.168.0.1
    sudo ip netns exec cont_vlan100 ping -c 3 8.8.8.8

  [Server 2 - VM, por consola VNC tras asignar la IP estatica]
    ip -br addr
    arping -c 3 192.168.0.1
    ping -c 3 192.168.0.1
    ping -c 3 8.8.8.8
EOF
