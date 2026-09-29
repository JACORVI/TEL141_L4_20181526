#!/bin/bash
# create_container.sh
# NOTA: este script NO es parte de la tabla de scripts del informe previo.
# Lo agrego porque el diagrama de las Actividades 1-3 del Reporte Final
# muestra "Contenedores" en el Server 1 conectados por veth a las VLANs,
# y ninguno de los 9 scripts del informe previo cubre esa pieza (solo VMs).
#
# Asuncion (CONFIRMAR CON EL JEFE DE PRACTICA): el "contenedor" es un
# Linux Network Namespace con un par veth conectado al OVS 'br-int',
# igual al patron ya usado para el namespace de DHCP. Si en realidad
# esperan un contenedor Docker, este script habria que reescribirlo.
#
# Crea un namespace con una interfaz veth conectada al OVS con el VLAN ID
# indicado, y le asigna una IP dentro de esa red (por DHCP o estatica).
#
# Parametros de entrada:
#   $1 : Nombre del contenedor/namespace
#   $2 : Nombre del bridge OVS (ej. br-int)
#   $3 : VLAN ID
#   $4 : IP estatica a asignar en formato CIDR (ej. 192.168.0.50/24),
#        o "dhcp" para obtenerla por DHCP (requiere que la VLAN ya
#        tenga el servicio DHCP levantado via create_network_vlan.sh)
#
# Uso:
#   ./create_container.sh cont_vlan100 br-int 100 dhcp
#   ./create_container.sh cont_vlan200 br-int 200 192.168.2.50/24
#
# Ejecucion remota (segun guia del laboratorio):
#   ssh user@remote-node-ip 'sudo bash -s' < ./create_container.sh "cont_vlan100" "br-int" "100" "dhcp"

set -euo pipefail

if [[ $# -lt 4 ]]; then
    echo "Uso: $0 <nombre_contenedor> <nombre_ovs> <vlan_id> <ip_cidr|dhcp>" >&2
    exit 1
fi

NAME=$1
OVS_NAME=$2
VLAN_ID=$3
IP_MODE=$4

# Los nombres de interfaz en Linux tienen un limite de 15 caracteres, asi
# que no podemos usar el nombre del contenedor tal cual si es largo. Se
# genera un sufijo corto y reproducible a partir de un hash del nombre.
# El lado que ira dentro del namespace se crea con un nombre temporal
# unico (para no chocar con una interfaz ya existente en el namespace
# raiz, como el propio 'eth0' de administracion del servidor) y luego,
# ya dentro del namespace, se renombra a 'eth0' para mayor claridad.
HASH=$(echo -n "$NAME" | md5sum | cut -c1-8)
VETH_HOST="vh-${HASH}"
VETH_NS_TMP="vn-${HASH}"
VETH_NS="eth0"

# Crear el namespace si no existe (se verifica el archivo real en
# /run/netns en vez de parsear la salida de 'ip netns list', que en
# algunos sistemas incluye texto extra como "(id: 0)" y rompe el grep -qx)
if [[ ! -e "/run/netns/$NAME" ]]; then
    echo "[create_container] Creando namespace '$NAME'..."
    ip netns add "$NAME"
else
    echo "[create_container] El namespace '$NAME' ya existe, se omite creacion."
fi

# Crear el par veth (lado host <-> lado namespace) si no existe
if ! ip link show "$VETH_HOST" &>/dev/null; then
    echo "[create_container] Creando par veth '$VETH_HOST' <-> '$VETH_NS' (namespace '$NAME')..."
    ip link add "$VETH_HOST" type veth peer name "$VETH_NS_TMP"
    ip link set "$VETH_NS_TMP" netns "$NAME"
    ip netns exec "$NAME" ip link set "$VETH_NS_TMP" name "$VETH_NS"
fi

# Conectar el extremo del host al OVS con el VLAN ID indicado
if ! ovs-vsctl list-ports "$OVS_NAME" | grep -qx "$VETH_HOST"; then
    echo "[create_container] Conectando '$VETH_HOST' al OVS '$OVS_NAME' (VLAN $VLAN_ID)..."
    ovs-vsctl add-port "$OVS_NAME" "$VETH_HOST" tag="$VLAN_ID"
fi
ip link set dev "$VETH_HOST" up

# Activar las interfaces dentro del namespace
ip netns exec "$NAME" ip link set dev "$VETH_NS" up
ip netns exec "$NAME" ip link set dev lo up

# Asignar direccionamiento
if [[ "$IP_MODE" == "dhcp" ]]; then
    if ! command -v dhclient >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y isc-dhcp-client
    fi
    echo "[create_container] Solicitando IP por DHCP dentro del namespace..."
    ip netns exec "$NAME" dhclient "$VETH_NS"
else
    echo "[create_container] Asignando IP estatica $IP_MODE..."
    ip netns exec "$NAME" ip addr add "$IP_MODE" dev "$VETH_NS" 2>/dev/null || true

    # Con IP estatica no hay DHCP que configure la ruta por defecto (a
    # diferencia del modo dhcp, donde dhclient ya la deja lista), asi que
    # la agregamos a mano usando el primer host del rango como gateway
    # (convencion usada en create_network_vlan.sh: gw_vlan<ID> = primer IP
    # utilizable del CIDR).
    NET_ADDR=${IP_MODE%/*}
    GATEWAY=$(echo "$NET_ADDR" | awk -F. '{print $1"."$2"."$3".1"}')
    echo "[create_container] Agregando ruta por defecto via $GATEWAY..."
    ip netns exec "$NAME" ip route replace default via "$GATEWAY" dev "$VETH_NS"
fi

echo "[create_container] Contenedor '$NAME' listo (VLAN $VLAN_ID)."
ip netns exec "$NAME" ip -br addr
