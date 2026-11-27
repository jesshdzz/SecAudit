# shellcheck shell=sh
# Módulo 1 — Usuarios y contraseñas.
# Prefijo de ids: USR-NNN

# shellcheck disable=SC2034 # lo lee auditor.sh --list
MOD_TITLE="Usuarios y contraseñas"
MOD_NAME=usuarios

# Rutas sobreescribibles para pruebas con tests/fixtures/.
USR_PASSWD=${USR_PASSWD:-/etc/passwd}
USR_SHADOW=${USR_SHADOW:-/etc/shadow}
USR_GROUP=${USR_GROUP:-/etc/group}
USR_LOGIN_DEFS=${USR_LOGIN_DEFS:-/etc/login.defs}
USR_PWQUALITY=${USR_PWQUALITY:-/etc/security/pwquality.conf}

# Umbrales
USR_MAX_DAYS_LIMIT=90
USR_MIN_LEN_REQUIRED=8
USR_MIN_LEN_RECOMMENDED=12
USR_SUDO_MAX_MEMBERS=3

# _usr_defs CLAVE -> valor en login.defs
_usr_defs() {
  [ -r "$USR_LOGIN_DEFS" ] || return 0
  awk -v k="$1" '$1 == k { v = $2 } END { print v }' "$USR_LOGIN_DEFS"
}

# USR-001: cuentas distintas de root con UID 0
_usr_uid0() {
  _t="Cuentas con UID 0 además de root"
  if [ ! -r "$USR_PASSWD" ]; then
    emit USR-001 "$MOD_NAME" CRITICA SKIP "$_t" "No se pudo leer $USR_PASSWD" "-"
    return
  fi
  _list=$(awk -F: '$3 == 0 && $1 != "root" { printf "%s%s", s, $1; s = "," }' "$USR_PASSWD")
  if [ -n "$_list" ]; then
    emit USR-001 "$MOD_NAME" CRITICA FAIL "$_t" \
      "UID 0: $_list. Toda cuenta con UID 0 tiene privilegios completos de root." \
      "Asignar un UID propio con 'usermod -u <uid> <usuario>' o eliminarla con 'userdel <usuario>'"
  else
    emit USR-001 "$MOD_NAME" CRITICA OK "$_t" "Solo root tiene UID 0" "-"
  fi
}

# USR-002: cuentas con el campo de contraseña vacío en /etc/shadow
_usr_empty_pw() {
  _t="Cuentas sin contraseña"
  if [ ! -r "$USR_SHADOW" ]; then
    emit USR-002 "$MOD_NAME" CRITICA SKIP "$_t" "No se pudo leer $USR_SHADOW (¿sin root?)" "-"
    return
  fi
  _list=$(awk -F: '$2 == "" { printf "%s%s", s, $1; s = "," }' "$USR_SHADOW")
  if [ -n "$_list" ]; then
    emit USR-002 "$MOD_NAME" CRITICA FAIL "$_t" \
      "Sin contraseña: $_list. Cualquiera puede iniciar sesión con estas cuentas." \
      "Definir contraseña con 'passwd <usuario>' o bloquear con 'passwd -l <usuario>'"
  else
    emit USR-002 "$MOD_NAME" CRITICA OK "$_t" "Todas las cuentas tienen contraseña o están bloqueadas" "-"
  fi
}

# USR-003: caducidad máxima de contraseñas (PASS_MAX_DAYS)
_usr_max_days() {
  _t="Caducidad máxima de contraseñas (PASS_MAX_DAYS)"
  _sug="Poner 'PASS_MAX_DAYS $USR_MAX_DAYS_LIMIT' en $USR_LOGIN_DEFS y aplicarlo a cuentas existentes con 'chage -M $USR_MAX_DAYS_LIMIT <usuario>'"
  if [ ! -r "$USR_LOGIN_DEFS" ]; then
    emit USR-003 "$MOD_NAME" MEDIA SKIP "$_t" "No existe $USR_LOGIN_DEFS" "-"
    return
  fi
  _v=$(_usr_defs PASS_MAX_DAYS)
  case $_v in
  '' | *[!0-9]*)
    emit USR-003 "$MOD_NAME" MEDIA WARN "$_t" "PASS_MAX_DAYS no está definido" "$_sug"
    ;;
  *)
    if [ "$_v" -gt "$USR_MAX_DAYS_LIMIT" ]; then
      emit USR-003 "$MOD_NAME" MEDIA FAIL "$_t" \
        "PASS_MAX_DAYS=$_v (> $USR_MAX_DAYS_LIMIT). Una contraseña filtrada sigue siendo válida indefinidamente." \
        "$_sug"
    else
      emit USR-003 "$MOD_NAME" MEDIA OK "$_t" "PASS_MAX_DAYS=$_v" "-"
    fi
    ;;
  esac
}

# USR-004: longitud mínima de contraseña.
# pam_pwquality (minlen) tiene prioridad; PASS_MIN_LEN de login.defs es el respaldo.
_usr_min_len() {
  _t="Longitud mínima de contraseña"
  _src=""
  _v=""
  set --
  [ -r "$USR_PWQUALITY" ] && set -- "$USR_PWQUALITY"
  for _f in "$USR_PWQUALITY".d/*.conf; do
    [ -r "$_f" ] && set -- "$@" "$_f"
  done
  if [ $# -gt 0 ]; then
    # Los archivos de .d/ se leen después y sobreescriben al principal.
    _v=$(awk '{ sub(/#.*/, ""); gsub(/[ \t]/, "") } /^minlen=/ { v = substr($0, 8) } END { print v }' "$@")
    [ -n "$_v" ] && _src="pwquality (minlen)"
  fi
  if [ -z "$_v" ]; then
    _v=$(_usr_defs PASS_MIN_LEN)
    [ -n "$_v" ] && _src="login.defs (PASS_MIN_LEN)"
  fi

  _sug="Definir 'minlen = $USR_MIN_LEN_RECOMMENDED' en $USR_PWQUALITY (requiere pam_pwquality: libpwquality en Fedora, libpam-pwquality en Debian/Ubuntu)"
  case $_v in
  '' | *[!0-9]*)
    emit USR-004 "$MOD_NAME" MEDIA WARN "$_t" "No hay una longitud mínima explícita configurada" "$_sug"
    ;;
  *)
    if [ "$_v" -lt "$USR_MIN_LEN_REQUIRED" ]; then
      emit USR-004 "$MOD_NAME" MEDIA FAIL "$_t" \
        "$_src=$_v (< $USR_MIN_LEN_REQUIRED). Las contraseñas cortas se rompen por fuerza bruta." "$_sug"
    elif [ "$_v" -lt "$USR_MIN_LEN_RECOMMENDED" ]; then
      emit USR-004 "$MOD_NAME" MEDIA WARN "$_t" \
        "$_src=$_v (recomendado >= $USR_MIN_LEN_RECOMMENDED)" "$_sug"
    else
      emit USR-004 "$MOD_NAME" MEDIA OK "$_t" "$_src=$_v" "-"
    fi
    ;;
  esac
}

# USR-005: cuentas de sistema (UID < UID_MIN) con shell interactivo
_usr_system_shells() {
  _t="Cuentas de sistema con shell interactivo"
  if [ ! -r "$USR_PASSWD" ]; then
    emit USR-005 "$MOD_NAME" MEDIA SKIP "$_t" "No se pudo leer $USR_PASSWD" "-"
    return
  fi
  _uid_min=$(_usr_defs UID_MIN)
  case $_uid_min in '' | *[!0-9]*) _uid_min=1000 ;; esac
  # Shell vacío equivale a /bin/sh. sync/shutdown/halt son cuentas especiales sin login.
  _list=$(awk -F: -v min="$_uid_min" '
        $1 != "root" && $3 < min && $7 !~ /(nologin|false|sync|shutdown|halt)$/ {
            printf "%s%s(%s)", s, $1, ($7 == "" ? "/bin/sh" : $7); s = ","
        }' "$USR_PASSWD")
  if [ -n "$_list" ]; then
    emit USR-005 "$MOD_NAME" MEDIA FAIL "$_t" \
      "$_list. Si un servicio se compromete, su cuenta permite obtener una shell." \
      "Quitar el shell con 'usermod -s /usr/sbin/nologin <usuario>'"
  else
    emit USR-005 "$MOD_NAME" MEDIA OK "$_t" "Ninguna cuenta con UID < $_uid_min tiene shell interactivo" "-"
  fi
}

# USR-006: miembros del grupo administrativo (sudo / wheel)
_usr_sudo_members() {
  _g=${SUDO_GROUP:-}
  _t="Miembros del grupo administrativo"
  if [ -z "$_g" ] || [ ! -r "$USR_GROUP" ] || ! grep -q "^$_g:" "$USR_GROUP"; then
    emit USR-006 "$MOD_NAME" MEDIA SKIP "$_t" "No se encontró el grupo sudo/wheel" "-"
    return
  fi
  # Miembros secundarios (/etc/group) + usuarios con ese grupo como primario (/etc/passwd).
  _out=$(awk -F: -v g="$_g" '
        NR == FNR { if ($1 == g) { gid = $3; n = split($4, m, ","); for (i = 1; i <= n; i++) if (m[i] != "") u[m[i]] = 1 } next }
        gid != "" && $4 == gid { u[$1] = 1 }
        END { c = 0; for (k in u) { l = l (c ? "," : "") k; c++ } print c " " l }
    ' "$USR_GROUP" "$USR_PASSWD")
  _n=${_out%% *}
  _list=${_out#* }

  if [ "$_n" -gt "$USR_SUDO_MAX_MEMBERS" ]; then
    emit USR-006 "$MOD_NAME" MEDIA WARN "$_t ($_g)" \
      "$_n miembros: $_list. Cada cuenta con sudo es una vía directa a root." \
      "Revisar la lista y retirar a quien no lo necesite con 'gpasswd -d <usuario> $_g'"
  else
    emit USR-006 "$MOD_NAME" MEDIA OK "$_t ($_g)" "$_n miembros: ${_list:-ninguno}" "-"
  fi
}

mod_run() {
  _usr_uid0
  _usr_empty_pw
  _usr_max_days
  _usr_min_len
  _usr_system_shells
  _usr_sudo_members
}
