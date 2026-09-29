#!/bin/bash
# create_vm.sh
# Crea una VM con las consideraciones dadas en el laboratorio 3 (interfaz TAP
# conectada al OVS, disco de arranque QCOW2 con backing file, puerto VNC):
#   1. Crea la VM con su interfaz TAP, disco de arranque y puerto VNC.
#   2. Para el disco de arranque, detecta si existe la imagen base; de no
#      existir, la descarga.
#
# Ademas del puerto VNC (grafico), la VM expone una consola serial por
# telnet en el puerto (VNC_PORT + 100), para poder operarla 100% desde
# terminal sin necesidad de un visor VNC:
#   telnet <ip_del_servidor> <VNC_PORT+100>
# (las imagenes cirros ya tienen un getty habilitado en ttyS0 por defecto).
#
# Parametros de entrada:
#   $1 : Nombre de la VM
#   $2 : Nombre del bridge OVS al que se conecta (ej. br-int)
#   $3 : VLAN ID
#   $4 : Puerto VNC (ej. 5901 -> display :1, consola serial en 6001)
#
# Uso:
#   ./create_vm.sh vm1 br-int 100 5901
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'bash -s' < ./create_vm.sh "vm1" "br-int" "100" "5901"

set -euo pipefail

if [[ $# -lt 4 ]]; then
    echo "Uso: $0 <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>" >&2
    exit 1
fi

VM_NAME=$1
OVS_NAME=$2
VLAN_ID=$3
VNC_PORT=$4

VM_DIR="/home/ubuntu/vms"
BASE_IMAGE_NAME="cirros-0.5.1-x86_64-disk.img"
BASE_IMAGE_URL="http://download.cirros-cloud.net/0.5.1/${BASE_IMAGE_NAME}"

DISK="${VM_DIR}/${VM_NAME}_disk.qcow2"
TAP="${VM_NAME}_tap"
PID_FILE="${VM_DIR}/${VM_NAME}.pid"

mkdir -p "$VM_DIR"
cd "$VM_DIR"

# 2. Detectar si existe la imagen base; de no existir, descargarla.
if [[ ! -f "$BASE_IMAGE_NAME" || ! -s "$BASE_IMAGE_NAME" ]]; then
    echo "[create_vm] Imagen base no encontrada, descargando..."
    if ! wget -q "$BASE_IMAGE_URL" -O "$BASE_IMAGE_NAME"; then
        rm -f "$BASE_IMAGE_NAME"
        echo "[create_vm] ERROR: no se pudo descargar la imagen base desde $BASE_IMAGE_URL" >&2
        exit 1
    fi
else
    echo "[create_vm] Imagen base '$BASE_IMAGE_NAME' ya existe."
fi

# Crear el disco de arranque (delta) de la VM a partir de la imagen base
if [[ ! -f "$DISK" ]]; then
    echo "[create_vm] Creando disco de arranque '$DISK'..."
    qemu-img create -f qcow2 -b "$BASE_IMAGE_NAME" -F qcow2 "$DISK"
else
    echo "[create_vm] El disco '$DISK' ya existe, se omite creacion."
fi

# 1. Crear la interfaz TAP y conectarla al OVS con el VLAN ID indicado
if ! ip link show "$TAP" &>/dev/null; then
    echo "[create_vm] Creando interfaz TAP '$TAP'..."
    ip tuntap add mode tap name "$TAP"
fi

if ! ovs-vsctl list-ports "$OVS_NAME" | grep -qx "$TAP"; then
    echo "[create_vm] Conectando '$TAP' al OVS '$OVS_NAME' (VLAN $VLAN_ID)..."
    ovs-vsctl add-port "$OVS_NAME" "$TAP" tag="$VLAN_ID"
fi

ip link set dev "$TAP" up

# Generar una direccion MAC reproducible a partir del nombre de la VM,
# usando el prefijo estandar de QEMU/KVM (52:54:00) como OUI.
HASH=$(echo -n "$VM_NAME" | md5sum | cut -c1-6)
MAC="52:54:00:${HASH:0:2}:${HASH:2:2}:${HASH:4:2}"

# Puerto VNC -> display de QEMU (5900 + display = puerto)
VNC_DISPLAY=$(( VNC_PORT - 5900 ))

# Puerto de consola serial por telnet, derivado del puerto VNC
SERIAL_PORT=$(( VNC_PORT + 100 ))

# Usar aceleracion KVM solo si el procesador la soporta y /dev/kvm existe
KVM_FLAG=""
if [[ -e /dev/kvm ]] && grep -qE 'vmx|svm' /proc/cpuinfo; then
    KVM_FLAG="-enable-kvm"
fi

echo "[create_vm] Iniciando VM '$VM_NAME' (MAC $MAC, VNC :$VNC_DISPLAY, consola serial telnet puerto $SERIAL_PORT)..."
# shellcheck disable=SC2086
qemu-system-x86_64 \
    $KVM_FLAG \
    -vnc "0.0.0.0:${VNC_DISPLAY}" \
    -serial "telnet:0.0.0.0:${SERIAL_PORT},server,nowait" \
    -netdev tap,id=tap1,ifname="${TAP}",script=no,downscript=no \
    -device e1000,netdev=tap1,mac="${MAC}" \
    -daemonize \
    -pidfile "$PID_FILE" \
    "$DISK"

echo "[create_vm] VM '$VM_NAME' creada correctamente (PID $(cat "$PID_FILE"))."
echo "[create_vm] Consola por terminal: telnet <ip_de_este_servidor> ${SERIAL_PORT}"
