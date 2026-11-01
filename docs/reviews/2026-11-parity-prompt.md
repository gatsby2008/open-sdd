# Prompt — paridad de open-sdd con los cambios de sdd-plugin del 2026-11-01

Encargo que lleva a open-sdd los cambios hechos en sdd-plugin el 2026-11-01:
las features #1 y #2 de su `main` (`ecb8137`, `ce7215b`) y los 10 commits de su
branch `review-improvements` (`33b39c3`..`a5f61f6`). El detalle de cada cambio
está en `docs/reviews/2026-11-changes-prompt.md` de sdd-plugin (puntos A1–A2 y
B1–B10); acá se dice cómo portarlo.

````markdown
Trabajás sobre open-sdd (`~/team/Yield/open-sdd`), en una branch `review-improvements` creada desde main. Leé primero `~/team/Yield/sdd-plugin/docs/reviews/2026-11-changes-prompt.md` (los puntos A y B) y `git log c7e2311..review-improvements` en sdd-plugin: es la referencia de cada cambio.

`open-sdd` implementa el mismo pipeline sin Claude Code. Antes de portar, leé su AGENTS.md y respetá su arquitectura.

| sdd-plugin | open-sdd |
|---|---|
| `/sdd:<x>` | `/f-<x>`; los comandos de docs son `/doc-*`, sin prefijo |
| `skills/<x>/SKILL.md` + `REFERENCE.md` | `commands/<x>.sh` (imprime contexto e instrucciones) + `agent/PIPELINE.md` (protocolo) |
| `lib/*.py` | `engine/*.py`, expuesto como subcomando de `engine/cli.py` |
| `lib/tests/` | `tests/` |
| `bash commands/check.sh` (del plugin) | `python3 -m unittest discover -s tests -p 'test_*.py'` + `bash tests/smoke.sh` + `bash tests/check-sdd-surface-parity.sh` + `bash tests/check-install-parity.sh` |

Restricciones extra:
- Mismas reglas que en sdd-plugin: consultame antes de borrar, renombrar o cambiar el formato de `.specwork/`; un commit por punto; sin push.
- Si el port necesita un comando nuevo, registralo en `install.sh` y alineá el conteo con README.
- Mantené `HIGH_KW` de `commands/triage.sh` en sincronía con `engine/cli.py::triage`.

### C1. Conformidad con el spec y promoción de reglas (= A1)
- Agregá ids `**B<n>**` a `## Behavior` en `templates/spec.md`, asignados por `/f-spec` sin renumerar.
- `/f-implement` etiqueta los tests con `spec: B<n>`.
- Portá `conformance.py` a `engine/` con un subcomando `conformance-check <slug>`, advisory, que corre `commands/commit.sh`.
- Portá `promote.py` a `engine/` y el Step 6.5 a `commands/close.sh`. El destino es `.opensdd/service-rules.md`, no `.claude/`. Se salta si `SDD_NON_INTERACTIVE=1`.
- Tests en `tests/test_conformance.py` y `tests/test_promote.py`.

### C2. Auditor high-risk advisory (= A2)
- `engine/audit.py` (`audit-required` / `audit-record`) con el recibo en `.specwork/_review/<slug>-audit.json`, fail-open.
- `commands/commit.sh` imprime la instrucción de correr `/f-code-review` en modo auditor solo cuando el nivel es high-risk y el diff cambió. Nunca bloquea.

### C3. Corregir la documentación desactualizada (= B1)
- `docs/concepts.md` §Gates no coincide con el código:
  - El gate de cobertura de `/f-commit` es STRICT (`engine coverage-check`), pero el doc lo describe como un chequeo soft de `/f-code-review`.
  - Falta el quality gate `check.sh`.
  - Agregá los dos advisory (C1, C2) y, si se acepta C4, plan-required.
- Revisá `docs/pipeline.md`, `docs/learning/*` (cheatsheet, flashcards, key-concepts) y `docs/presentation/*` buscando el mismo tipo de drift: conteos, nombres de comandos y punteros.

### C4. Override del nivel `/f-spec --tier` (= B2) — preguntame antes
- `open-sdd` no tiene gate plan-required: high-risk incluye `f-plan` en `recommended_path`, pero `/f-implement` entra en modo no-plan si no hay plan. Agregar el gate es una regla nueva; confirmame antes de hacerlo.
- Independientemente de eso, implementá el override en `commands/triage.sh` / `engine/cli.py::triage`:
  - `--tier <trivial|focused|standard|high-risk|auto> "<reason>"`, con el reason obligatorio (exit 2 sin escribir si falta).
  - Bloque `override {tier, reason, auto_tier, auto_why}` en path.json; sticky; `auto` lo elimina.
  - Recalculá `recommended_path` y `skip` del nivel forzado y actualizá `ticket_type` y `complexity` en state.json.
  - El summary muestra la línea "Override: forced X (auto: Y — reason)".
- Tests en `tests/test_cli.py` o en `tests/triage_scenarios.sh`: forzar más bajo, forzar más alto, reason obligatorio, sticky y auto.

### C5. Adelgazar el protocolo de implement (= B3)
- Medí las palabras de `agent/PIPELINE.md` (~4370) y de `commands/*.sh`. PIPELINE.md se carga globalmente, así que es el equivalente al peso de un SKILL.md.
- Aplicá el mismo criterio que en B3 a la sección de implement: lo que se necesita siempre queda; el detalle bajo demanda (mensajes de abort, matriz de fallos, escalamiento, plantillas de salida) pasa a `templates/pipeline-reference.md`, con punteros.
- Comportamiento sin cambios: los gates siguen en `engine implement-check`.
- Listá a dónde fue a parar cada parte.

### C6. check.sh bloquea el push, no el commit (= B4) — preguntame antes
- Hoy `commands/commit.sh` corre check.sh y graba `checked_sha`, y `commands/mr.sh` saltea la validación si HEAD coincide. Pasar a solo-push cambia el comportamiento de `/f-commit` y deja sin uso `checked_sha`; confirmame antes.
- Si se aprueba:
  - Sacá el quality gate de `commit.sh`; el gate de cobertura STRICT se queda.
  - `mr.sh` valida siempre antes del push. Decidí qué hacer con `checked_sha`.
  - Actualizá AGENTS.md, `docs/setup.md` ("Validation script"), `templates/check.sh.example` y las flashcards #16, #46, #52 y #59.

### C7. Slug desde la branch (= B5–B7) — verificar y fijar con tests
- `open-sdd` ya deriva slugs en minúsculas, pero en cuatro lugares distintos:
  - `slugify` en `commands/start.sh`;
  - `resolve_slug` en `engine/gates.py`;
  - `engine/cli.py` (subcomando de branch);
  - `commands/resync.sh`.
- Verificá que los cuatro den el mismo resultado:
  - Ojo: los prefijos no coinciden. start.sh y cli.py usan feature|bugfix|hotfix|release, pero `resolve_slug` corta cualquier prefijo `x/`.
  - Casos: `feature/PROJ-123 → proj-123`, `feature/IR-70.1 → ir-70-1`, `feature/my_slug → my-slug`.
- Si difieren, unificalos detrás de un solo helper de `engine/` y agregá tests que fijen esos casos.
- No hace falta el fallback por mayúsculas: nunca se generaron slugs con mayúsculas.

### C8. Propuestas y anexo (= B8–B10)
- No copies `docs/reviews/2026-11-improvements.md` de sdd-plugin (ese repo no puede nombrar a open-sdd en archivos versionados).
- En este repo, creá `docs/reviews/2026-11-improvements-impact.md` con el impacto en open-sdd de las propuestas 4, 5 y 6 y del anexo. Por ejemplo: el anexo implica consolidar los `/doc-*-query` en un solo `/doc-ask`, y `check-sdd-surface-parity.sh` hoy exige los 8 comandos doc.

## Entrega
- Para cada punto: un commit, con las cuatro verificaciones de la tabla en verde.
- Informe final: matriz de paridad sdd-plugin ↔ open-sdd, con cada punto A/B, su par C y el estado (hecho, pendiente de OK o no aplica), y palabras de PIPELINE.md antes y después.
````

## Notas de ejecución (2026-11-01)

Se ejecutó en la branch `review-improvements` (commits `5526e24`..). C4 y C6 se
aprobaron. Hubo dos desvíos del prompt, porque el prompt partía de supuestos
equivocados:

- **C1:** las reglas promovidas van a `.claude/rules/*.md`, no a
  `.opensdd/service-rules.md`. `.opensdd/` está en el .gitignore y `/f-close` lo
  borra justo después de la promoción. `/f-start` ya sincroniza `.claude/rules/` en
  `.opensdd/`. `engine/promote.py` rechaza cualquier otro destino.
- **C5:** el detalle bajo demanda va a un archivo nuevo, `agent/REFERENCE.md`, y no a
  `templates/pipeline-reference.md`. `install.sh` instala ese template como
  instrucciones globales de opencode, así que se carga en todas las sesiones.

Impacto de las propuestas 4–6 y hallazgos: `docs/reviews/2026-11-improvements-impact.md`.
