#!/bin/bash
# delete_vm.sh
# Elimina una VM y sus recursos relacionados (proceso QEMU, puerto OVS,
# interfaz TAP, disco de arranque). Para el disco de arranque, detecta si
# la imagen base ya no tiene deltas (otras VMs dependiendo de ella); de ser
# asi, tambien elimina la imagen base.
#
# Parametros de entrada:
#   $1 : Nombre de la VM
#   $2 : Nombre del bridge OVS al que estaba conectada (ej. br-int)
#   $3 : VLAN ID
#   $4 : Puerto VNC
#
# Uso:
#   ./delete_vm.sh vm1 br-int 100 5901
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./delete_vm.sh "vm1" "br-int" "100" "5901"

set -uo pipefail

if [[ $# -lt 4 ]]; then
    echo "Uso: $0 <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>" >&2
    exit 1
fi

VM_NAME=$1
OVS_NAME=$2
# VLAN_ID ($3) y VNC_PORT ($4) se reciben por consistencia con create_vm.sh,
# aunque no son necesarios para identificar los recursos a eliminar.

VM_DIR="/home/ubuntu/vms"
BASE_IMAGE_NAME="cirros-0.5.1-x86_64-disk.img"
DISK="${VM_DIR}/${VM_NAME}_disk.qcow2"
TAP="${VM_NAME}_tap"
PID_FILE="${VM_DIR}/${VM_NAME}.pid"

# 1. Detener el proceso QEMU de la VM
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "[delete_vm] Deteniendo proceso QEMU de '$VM_NAME' (PID $PID)..."
        kill "$PID"
        sleep 1
    fi
    rm -f "$PID_FILE"
else
    echo "[delete_vm] No se encontro pidfile para '$VM_NAME', se omite kill."
fi

# 2. Eliminar el puerto OVS y la interfaz TAP
if ovs-vsctl list-ports "$OVS_NAME" 2>/dev/null | grep -qx "$TAP"; then
    echo "[delete_vm] Eliminando puerto OVS '$TAP' de '$OVS_NAME'..."
    ovs-vsctl del-port "$OVS_NAME" "$TAP"
fi

if ip link show "$TAP" &>/dev/null; then
    echo "[delete_vm] Eliminando interfaz TAP '$TAP'..."
    ip link del "$TAP"
fi

# 3. Eliminar el disco de arranque (delta) de la VM
if [[ -f "$DISK" ]]; then
    echo "[delete_vm] Eliminando disco '$DISK'..."
    rm -f "$DISK"
else
    echo "[delete_vm] El disco '$DISK' no existe, se omite eliminacion."
fi

# 4. Verificar si la imagen base ya no tiene deltas; de ser asi, eliminarla
cd "$VM_DIR" 2>/dev/null || exit 0

TIENE_DELTAS=0
for f in "$VM_DIR"/*_disk.qcow2; do
    [[ -e "$f" ]] || continue
    # -U (force share) es necesario: otras VMs pueden seguir corriendo y
    # tener su disco bloqueado (write lock). Sin -U, qemu-img info fallaria
    # silenciosamente y el script creeria (de forma incorrecta y peligrosa)
    # que ya no quedan deltas, borrando la imagen base en uso.
    BACKING=$(qemu-img info -U "$f" 2>/dev/null | grep "^backing file:" | awk '{print $3}' | xargs -n1 basename 2>/dev/null)
    if [[ "$BACKING" == "$BASE_IMAGE_NAME" ]]; then
        TIENE_DELTAS=1
        break
    fi
done

if [[ $TIENE_DELTAS -eq 0 && -f "$BASE_IMAGE_NAME" ]]; then
    echo "[delete_vm] Ninguna VM depende ya de '$BASE_IMAGE_NAME', eliminandola..."
    rm -f "$BASE_IMAGE_NAME"
else
    echo "[delete_vm] La imagen base sigue teniendo deltas, no se elimina."
fi

echo "[delete_vm] VM '$VM_NAME' eliminada correctamente."
