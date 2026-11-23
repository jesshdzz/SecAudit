# shellcheck shell=sh
# lib/common.sh — Utilidades compartidas por el orquestador y los módulos.
# Uso: . "$AUDITOR_ROOT/lib/common.sh"
#
# Variables que lee:
#   RESULTS_FILE     Destino de emit(). Vacío = stdout.
#   AUDITOR_LOG      Archivo de log. Por defecto /dev/null.
#   AUDITOR_VERBOSE  1 = también muestra INFO/DEBUG en stderr.

: "${AUDITOR_LOG:=/dev/null}"
: "${AUDITOR_VERBOSE:=0}"

# log NIVEL mensaje...   (NIVEL: DEBUG | INFO | WARN | ERROR)
log() {
  _log_lvl=$1
  shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_log_lvl" "$*" >>"$AUDITOR_LOG"
  case $_log_lvl in
  WARN | ERROR) printf '[%s] %s\n' "$_log_lvl" "$*" >&2 ;;
  *) if [ "$AUDITOR_VERBOSE" = 1 ]; then printf '[%s] %s\n' "$_log_lvl" "$*" >&2; fi ;;
  esac
  return 0
}

die() {
  log ERROR "$*"
  exit 1
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Se requieren privilegios de root (ejecuta con sudo o pkexec)."
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Convierte tabuladores y saltos de línea en espacios. Un campo vacío se
# vuelve "-" porque split() de Perl descarta campos vacíos al final.
_sanitize() {
  _san_v=$(printf '%s' "$1" | tr '\t\r\n' '   ')
  printf '%s' "${_san_v:--}"
}

# emit ID MODULO SEVERIDAD ESTADO TITULO DETALLE SUGERENCIA
# Única forma de escribir en results.tsv (ver contrato en docs/).
emit() {
  if [ $# -ne 7 ]; then
    log ERROR "emit: se esperaban 7 campos y llegaron $# (id=${1:-?})"
    return 1
  fi
  case $1 in
  [A-Z]*-[0-9][0-9][0-9]) ;;
  *)
    log ERROR "emit: id inválido '$1' (formato MOD-NNN)"
    return 1
    ;;
  esac
  case $3 in
  CRITICA | ALTA | MEDIA | BAJA) ;;
  *)
    log ERROR "emit: severidad inválida '$3' en $1"
    return 1
    ;;
  esac
  case $4 in
  OK | FAIL | WARN | SKIP) ;;
  *)
    log ERROR "emit: estado inválido '$4' en $1"
    return 1
    ;;
  esac

  _emit_line=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$1" "$(_sanitize "$2")" "$3" "$4" \
    "$(_sanitize "$5")" "$(_sanitize "$6")" "$(_sanitize "$7")")

  if [ -n "${RESULTS_FILE:-}" ]; then
    printf '%s\n' "$_emit_line" >>"$RESULTS_FILE"
  else
    printf '%s\n' "$_emit_line"
  fi
  log DEBUG "emit $1 $4"
}
