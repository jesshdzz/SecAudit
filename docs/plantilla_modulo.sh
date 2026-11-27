# shellcheck shell=sh
# Plantilla de módulo. Copiar a modules/NN_nombre.sh y reemplazar XXX/nombre.
# auditor.sh carga el archivo en un subshell y llama a mod_run().
# Disponibles: emit, log, has_cmd y las variables de lib/distro.sh.
#
# Reglas:
#   - Cada check emite exactamente UN registro: OK | FAIL | WARN | SKIP.
#   - Si falta una herramienta o archivo -> SKIP, nunca abortar.
#   - Mismo título en todos los estados; la evidencia va en DETALLE junto
#     con una línea de por qué es riesgo; SUGERENCIA = comando o cambio concreto.
#   - Prefijar funciones y variables internas (_xxx_) para no chocar con common.sh.

# shellcheck disable=SC2034 # lo lee auditor.sh --list
MOD_TITLE="Nombre legible del módulo"
MOD_NAME=nombre

# XXX-001: descripción breve del check
_xxx_ejemplo() {
  _t="Título corto del check"
  if ! has_cmd herramienta; then
    emit XXX-001 "$MOD_NAME" MEDIA SKIP "$_t" "herramienta no disponible" "-"
    return
  fi
  _valor=$(herramienta --opcion 2>/dev/null)
  if [ "$_valor" = "inseguro" ]; then
    emit XXX-001 "$MOD_NAME" MEDIA FAIL "$_t" \
      "Valor actual: $_valor. Por qué es un riesgo, en una línea." \
      "Comando o cambio concreto para corregirlo"
  else
    emit XXX-001 "$MOD_NAME" MEDIA OK "$_t" "Valor actual: $_valor" "-"
  fi
}

mod_run() {
  _xxx_ejemplo
}
