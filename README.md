# auditor-linux

Auditor de seguridad básico para Linux (Fedora, Ubuntu, Debian). Detecta configuraciones inseguras, las clasifica por severidad, calcula un puntaje global (0–100) y sugiere cómo corregirlas. Backend en POSIX `sh` + AWK; GUI en Perl-Tk.

## Requisitos

| Distro | Paquetes |
| --- | --- |
| Fedora | `perl-Tk` |
| Ubuntu / Debian | `perl-tk` |

`awk`, `sed`, `find`, `ss`, `sysctl` y `systemd` vienen en la instalación base de las tres distros.

## Uso

```sh
sudo ./auditor.sh               # todos los módulos
sudo ./auditor.sh -m 1,3        # por número
sudo ./auditor.sh -m usuarios   # por nombre
./auditor.sh -l                 # lista módulos implementados (no requiere root)
./auditor.sh -h                 # ayuda
```

Cada ejecución crea `reports/AAAAMMDD-HHMMSS/` con:

| Archivo | Contenido |
| --- | --- |
| `results.tsv` | Un registro por check (ver contrato abajo) |
| `summary.txt` | Resumen `clave=valor` generado por `awk/stats.awk` |
| `auditor.log` | Log de la ejecución |

La última línea de stdout es `RESULTS=<ruta>/results.tsv`, para que la GUI sepa qué cargar. Los archivos se crean con permisos `600` y se entregan al usuario que invocó `sudo`/`pkexec`.

## Contrato `results.tsv`

Campos separados por tabulador, sin encabezado; un campo vacío se escribe como `-`.

```
id  modulo  severidad  estado  titulo  detalle  sugerencia
```

- `id`: `MOD-NNN` (p. ej. `USR-001`)
- `severidad`: `CRITICA | ALTA | MEDIA | BAJA`
- `estado`: `OK | FAIL | WARN | SKIP`

## Estructura

```
auditor.sh        orquestador
lib/common.sh     emit(), log(), die(), require_root(), has_cmd()
lib/distro.sh     detect_distro(): DISTRO_*, PKG_MGR, FIREWALL, AUTH_LOG, SUDO_GROUP
modules/          NN_nombre.sh, uno por módulo
awk/              stats.awk, report_html.awk
gui/              auditor_gui.pl
tests/fixtures/   results.tsv de ejemplo
docs/             documentación y plantilla de módulo
```

## Agregar un módulo

1. Copiar `docs/plantilla_modulo.sh` a `modules/NN_nombre.sh`.
2. Definir `MOD_TITLE`, `MOD_NAME` y `mod_run()`; escribir resultados solo con `emit`.
3. Si falta una herramienta o archivo, emitir `SKIP` (el módulo nunca debe abortar).

Un archivo de módulo vacío o sin `mod_run()` se omite.

## Desarrollo

- Ramas cortas (`feat/mod-ssh`, `fix/distro-debian`) y PR con revisión de otra persona.
- Commits con Conventional Commits: `feat(usuarios): detectar UID 0 adicionales`.
- Antes de abrir PR:

```sh
shellcheck -s sh -x auditor.sh lib/*.sh modules/*.sh
sudo dash ./auditor.sh -m <tu_módulo>
```