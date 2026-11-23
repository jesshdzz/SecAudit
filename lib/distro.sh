# shellcheck shell=sh
# lib/distro.sh — Aísla las diferencias entre Fedora, Ubuntu y Debian.
# Requiere lib/common.sh. Uso: detect_distro
#
# Define:
#   DISTRO_ID       fedora | ubuntu | debian | ...
#   DISTRO_VERSION  VERSION_ID de os-release
#   DISTRO_NAME     PRETTY_NAME de os-release
#   DISTRO_FAMILY   fedora | debian | unknown
#   PKG_MGR         dnf | apt-get | none
#   FIREWALL        firewalld | ufw | nftables | none  (herramienta instalada;
#                   si está activa lo decide el módulo 4)
#   AUTH_LOG        ruta del log de autenticación, o "journal" si solo hay journald
#   SUDO_GROUP      wheel | sudo | ""

OS_RELEASE_FILE=${OS_RELEASE_FILE:-/etc/os-release}

# _osr_get CLAVE -> valor sin comillas
_osr_get() {
  sed -n "s/^$1=//p" "$OS_RELEASE_FILE" 2>/dev/null | head -n 1 |
    sed "s/^[\"']//; s/[\"']\$//"
}

_group_exists() {
  [ -r /etc/group ] && grep -q "^$1:" /etc/group
}

_detect_firewall() {
  if has_cmd firewall-cmd; then
    FIREWALL=firewalld
  elif has_cmd ufw; then
    FIREWALL=ufw
  elif has_cmd nft; then
    FIREWALL=nftables
  else
    FIREWALL=none
  fi
}

detect_distro() {
  if [ ! -r "$OS_RELEASE_FILE" ] && [ -r /usr/lib/os-release ]; then
    OS_RELEASE_FILE=/usr/lib/os-release
  fi
  [ -r "$OS_RELEASE_FILE" ] || log WARN "No se encontró os-release; se usarán valores por detección"

  DISTRO_ID=$(_osr_get ID)
  DISTRO_VERSION=$(_osr_get VERSION_ID)
  DISTRO_NAME=$(_osr_get PRETTY_NAME)
  _distro_like=$(_osr_get ID_LIKE)

  case " ${DISTRO_ID:-} ${_distro_like:-} " in
  *" fedora "* | *" rhel "*) DISTRO_FAMILY=fedora ;;
  *" debian "* | *" ubuntu "*) DISTRO_FAMILY=debian ;;
  *) DISTRO_FAMILY=unknown ;;
  esac

  case $DISTRO_FAMILY in
  fedora)
    PKG_MGR=dnf
    SUDO_GROUP=wheel
    _auth_file=/var/log/secure
    ;;
  debian)
    PKG_MGR=apt-get
    SUDO_GROUP=sudo
    _auth_file=/var/log/auth.log
    ;;
  *)
    log WARN "Distribución no soportada (${DISTRO_ID:-desconocida}); resultados aproximados"
    if has_cmd dnf; then PKG_MGR=dnf; elif has_cmd apt-get; then PKG_MGR=apt-get; else PKG_MGR=none; fi
    if _group_exists wheel; then SUDO_GROUP=wheel; elif _group_exists sudo; then SUDO_GROUP=sudo; else SUDO_GROUP=""; fi
    _auth_file=""
    ;;
  esac

  # Fedora y Debian 12 pueden no tener rsyslog: entonces todo está en journald.
  if [ -n "$_auth_file" ] && [ -f "$_auth_file" ]; then
    AUTH_LOG=$_auth_file
  else
    AUTH_LOG=journal
  fi

  _detect_firewall

  : "${DISTRO_ID:=unknown}" "${DISTRO_VERSION:=}" "${DISTRO_NAME:=$DISTRO_ID}"
  log INFO "Distro: $DISTRO_NAME | familia=$DISTRO_FAMILY pkg=$PKG_MGR firewall=$FIREWALL auth_log=$AUTH_LOG sudo_group=${SUDO_GROUP:-ninguno}"
}
