# SDD Pipeline — open-sdd

open-sdd está en `~/team/Yield/open-sdd/`.

## Comandos disponibles

| Chat | Lo que hace |
|------|-------------|
| `/f-start <texto o JIRA-123>` | Crea branch + spec scaffold |
| `/f-plan` | Descubre archivos, evalúa riesgos, escribe plan |
| `/f-implement` | Muestra spec + plan + primer target |
| `/f-implement --done N` | Marca target N como completado |
| `/f-pause` | Pausa el pipeline actual y stash todo el trabajo |
| `/f-resume` | Lista pipelines pausados y restaura el seleccionado |
| `/f-status` | Muestra el estado actual del pipeline |
| `/f-test-design` | Diseña casos de test para los cambios actuales |
| `/f-test-impl` | Implementa los archivos de test |
| `/f-commit` | Stage + commit semántico |
| `/f-spec-refine <contexto>` | Agrega contexto a la spec (archivos, jira, texto) |
| `/f-resync` | Resincroniza pipeline tras renombrar la branch |
| `/f-resync <nueva-branch>` | Renombra branch y resincroniza (atómico) |
| `/f-code-review` | Review de calidad/seguridad del diff actual |
| `/f-code-review --recheck` | Re-review comparando contra reporte anterior |
| `/f-help` | Muestra el estado del pipeline y el próximo paso |
| `/f-help overview` | Referencia completa del pipeline |
| `/f-review-address` | Revisa y responde comentarios del MR uno por uno |
| `/f-handoff` | Genera un pack de ejecución para otro agente/modelo |
| `/f-mr` | Push + crear MR en GitHub |
| `/f-close` | Borrar `.specwork/`, opcionalmente borrar branch |

## Modo de uso

Cuando ejecuto `/f-start`, corro `~/team/Yield/open-sdd/commands/start.sh`.
Cuando ejecuto `/f-plan`, corro `~/team/Yield/open-sdd/commands/plan.sh`.
Y así con cada comando.

Todos los comandos se ejecutan desde la raíz del proyecto actual.
