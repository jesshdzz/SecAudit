#!/bin/sh
# Ejecuta los módulos de modules/, escribe results.tsv y llama a awk/stats.awk.
set -u

AUDITOR_VERSION=0.1.0

AUDITOR_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# shellcheck source=lib/common.sh
. "$AUDITOR_ROOT/lib/common.sh"
# shellcheck source=lib/distro.sh
. "$AUDITOR_ROOT/lib/distro.sh"

usage() {
  cat <<EOF
Uso: sudo $0 [opciones]

  -m, --modules LISTA  Módulos a ejecutar, separados por coma (número o nombre).
                       Ej.: -m 1,3   -m usuarios,ssh   (por defecto: todos)
  -o, --output DIR     Directorio de salida (por defecto reports/AAAAMMDD-HHMMSS)
  -l, --list           Lista los módulos implementados (num<TAB>nombre<TAB>título)
  -v, --verbose        Muestra el log detallado en stderr
  -V, --version        Muestra la versión
  -h, --help           Muestra esta ayuda
EOF
}

MOD_FILTER=""
OUT_DIR=""
LIST_ONLY=0

while [ $# -gt 0 ]; do
  case $1 in
  -m | --modules)
    [ $# -ge 2 ] || die "Falta el valor de $1"
    MOD_FILTER=$2
    shift 2
    ;;
  -o | --output)
    [ $# -ge 2 ] || die "Falta el valor de $1"
    OUT_DIR=$2
    shift 2
    ;;
  -l | --list)
    LIST_ONLY=1
    shift
    ;;
  -v | --verbose)
    AUDITOR_VERBOSE=1
    shift
    ;;
  -V | --version)
    printf 'auditor %s\n' "$AUDITOR_VERSION"
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
done

# mod_selected NN_nombre.sh -> 0 si entra en el filtro -m
mod_selected() {
  [ -z "$MOD_FILTER" ] && return 0
  _sel_num=${1%%_*}
  _sel_name=${1#*_}
  _sel_name=${_sel_name%.sh}
  _sel_ifs=$IFS
  IFS=,
  set -f
  # shellcheck disable=SC2086 # se divide por comas a propósito
  set -- $MOD_FILTER
  set +f
  IFS=$_sel_ifs
  for _sel in "$@"; do
    case $_sel in
    '') ;;
    *[!0-9]*) [ "$_sel" = "$_sel_name" ] && return 0 ;;
    *) [ "$_sel" -eq "$_sel_num" ] && return 0 ;;
    esac
  done
  return 1
}

# Un módulo implementado define mod_run(). Los archivos vacíos se ignoran.
list_modules() {
  for _lm_f in "$AUDITOR_ROOT"/modules/[0-9][0-9]_*.sh; do
    [ -f "$_lm_f" ] || continue
    (
      MOD_TITLE=""
      # shellcheck disable=SC1090
      . "$_lm_f" >/dev/null 2>&1
      command -v mod_run >/dev/null 2>&1 || exit 0
      _lm_b=${_lm_f##*/}
      _lm_name=${_lm_b#*_}
      printf '%s\t%s\t%s\n' "${_lm_b%%_*}" "${_lm_name%.sh}" "${MOD_TITLE:-${_lm_name%.sh}}"
    )
  done
}

# Cada módulo corre en un subshell: si falla o aborta, la auditoría sigue.
run_module() {
  (
    # shellcheck disable=SC1090
    . "$1"
    if ! command -v mod_run >/dev/null 2>&1; then
      log WARN "${1##*/} no implementa mod_run(); se omite"
      exit 0
    fi
    mod_run
  )
  _rm_rc=$?
  [ "$_rm_rc" -eq 0 ] || log ERROR "El módulo ${1##*/} terminó con código $_rm_rc; se continúa"
}

main() {
  if [ "$LIST_ONLY" = 1 ]; then
    list_modules
    exit 0
  fi

  require_root

  OUT_DIR=${OUT_DIR:-$AUDITOR_ROOT/reports/$(date +%Y%m%d-%H%M%S)}
  mkdir -p -- "$(dirname -- "$OUT_DIR")" || die "No se pudo crear $(dirname -- "$OUT_DIR")"
  # Los resultados incluyen datos sensibles (p. ej. cuentas sin contraseña).
  umask 077
  mkdir -p -- "$OUT_DIR" || die "No se pudo crear $OUT_DIR"

  RESULTS_FILE=$OUT_DIR/results.tsv
  AUDITOR_LOG=$OUT_DIR/auditor.log
  : >"$RESULTS_FILE"
  : >"$AUDITOR_LOG"

  log INFO "auditor $AUDITOR_VERSION iniciado (filtro: ${MOD_FILTER:-todos})"
  detect_distro

  set --
  for _f in "$AUDITOR_ROOT"/modules/[0-9][0-9]_*.sh; do
    [ -f "$_f" ] || continue
    mod_selected "${_f##*/}" && set -- "$@" "$_f"
  done
  [ $# -gt 0 ] || die "Ningún módulo coincide con '${MOD_FILTER}'"

  _total=$#
  _i=0
  for _f in "$@"; do
    _i=$((_i + 1))
    printf '[%d/%d] %s\n' "$_i" "$_total" "${_f##*/}"
    log INFO "Ejecutando ${_f##*/}"
    run_module "$_f"
  done

  _stats=$AUDITOR_ROOT/awk/stats.awk
  if [ -s "$_stats" ]; then
    if awk -F '\t' -f "$_stats" "$RESULTS_FILE" >"$OUT_DIR/summary.txt"; then
      cat "$OUT_DIR/summary.txt"
    else
      log ERROR "stats.awk falló; revisa $AUDITOR_LOG"
    fi
  else
    log WARN "awk/stats.awk vacío o ausente: no se genera el resumen"
  fi

  # Devuelve la propiedad al usuario que invocó sudo/pkexec para que la GUI lea los resultados.
  _owner=${SUDO_UID:-${PKEXEC_UID:-}}
  if [ -n "$_owner" ]; then
    chown -R "$_owner" "$OUT_DIR" || log WARN "No se pudo cambiar el propietario de $OUT_DIR"
  fi

  log INFO "Auditoría terminada: $(wc -l <"$RESULTS_FILE" | tr -d ' ') checks"
  printf 'RESULTS=%s\n' "$RESULTS_FILE"
}

main
