#!/bin/bash
# deploy_actividad2.sh
# ACTIVIDAD N°2 del Reporte Final (3 pt):
#   "red con DHCP y sin salida a internet"
#
# Alcance (segun el template real TEL141_LAB4_RF_Template.docx):
#   - Una sola VLAN: VLAN 200 (192.168.2.0/24, gw 192.168.2.1)
#   - CON servicio DHCP
#   - SIN salida a Internet (no se llama internet_to_network.sh)
#   - Contenedor en Server 1 (VLAN 200) obtiene IP por DHCP
#   - VM en Server 2 (VLAN 200) obtiene IP por DHCP
#
# Se ejecuta DESDE EL SERVER 4 (Cliente), orquestando remotamente via SSH.
# Puede ejecutarse junto con deploy_actividad1.sh (VLANs distintas, no
# interfieren entre si) ya que la Actividad 3 (ruteo) necesita ambas activas.
#
# Uso: ./deploy_actividad2.sh

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

echo "=== ACTIVIDAD 2: VLAN 200 con DHCP y sin salida a Internet ==="

# 1. Inicializar nodos (idempotente si ya se corrio la Actividad 1)
run_remote "$SERVER3_IP" "$SCRIPT_DIR/init_master.sh" ens4
run_remote "$SERVER1_IP" "$SCRIPT_DIR/init_worker.sh" ens4
run_remote "$SERVER2_IP" "$SCRIPT_DIR/init_worker.sh" ens4

# 2. Crear la VLAN 200 en Server 3, CON DHCP habilitado
run_remote "$SERVER3_IP" "$SCRIPT_DIR/create_network_vlan.sh" 200 192.168.2.0/24 yes "192.168.2.10,192.168.2.200"

# NOTA: a diferencia de la Actividad 1, aqui NO se llama internet_to_network.sh
# -> no debe haber salida a Internet desde la VLAN 200.

# 3. Desplegar la VM en Server 2 (VLAN 200), obtiene IP por DHCP
run_remote "$SERVER2_IP" "$SCRIPT_DIR/create_vm.sh" vm_vlan200 br-int 200 5912
echo ">>> Recordar: dentro de la VM (VNC puerto 5912 -> display :12) ejecutar"
echo "    'sudo cirros-dhcpc up eth0' (o 'sudo dhclient eth0') para solicitar la IP por DHCP."

# 4. Desplegar el contenedor en Server 1 (VLAN 200), obtiene IP por DHCP
run_remote "$SERVER1_IP" "$SCRIPT_DIR/create_container.sh" cont_vlan200 br-int 200 dhcp

cat <<'EOF'

=== Actividad 2 desplegada. Evidencia a capturar para el Reporte Final: ===
  [Server 1 - contenedor: solicitar IP por DHCP, IP+MAC, gateway, conectividad]
    sudo ip netns exec cont_vlan200 dhclient eth0        # solicitar IP por DHCP
    sudo ip netns exec cont_vlan200 ip -br addr           # IP obtenida
    sudo ip netns exec cont_vlan200 ip link show eth0     # MAC de la interfaz
    sudo ip netns exec cont_vlan200 ip route               # default gateway obtenido
    sudo ip netns exec cont_vlan200 arping -c 3 192.168.2.1
    sudo ip netns exec cont_vlan200 ping -c 3 192.168.2.1

  [Server 2 - VM, por consola VNC: solicitar IP por DHCP, IP+MAC, gateway, conectividad]
    sudo cirros-dhcpc up eth0     # (cirros) solicitar IP por DHCP
    ip -br addr                    # IP obtenida
    ip link show eth0              # MAC de la interfaz
    ip route                       # default gateway obtenido
    arping -c 3 192.168.2.1
    ping -c 3 192.168.2.1
EOF
