# Impacto en open-sdd de las propuestas de sdd-plugin — noviembre 2026

Las propuestas viven en sdd-plugin, en `docs/reviews/2026-11-improvements.md`
(propuestas 4, 5 y 6, y el anexo de la 4). Ese repo no puede nombrar a open-sdd
en archivos versionados, así que el impacto de cada una se anota acá. Para mantener
la paridad, toda propuesta que se apruebe allá debería tener su par acá.

Esfuerzo: **S** ≤ 1 día · **M** 2–4 días · **L** ≥ 1 semana.

---

## 4. Separar el plugin (A: tres plugins, B: dos, C: no separar y adelgazar)

**No hay un equivalente directo.** open-sdd no es un plugin de Claude Code: un solo
`install.sh` registra todos los comandos en opencode. El prefijo de los comandos no
depende de un nombre de plugin (`/f-*` el pipeline, `/doc-*` y `/arch-query` los
companion). Separar no cambia ningún nombre.

- **C (adelgazar):** acá ya está aplicada en lo que más pesa. `agent/PIPELINE.md`
  se lee completo en cada comando y pasó de 4699 a ~1955 palabras, moviendo el
  detalle a `agent/REFERENCE.md`. El otro texto que se carga siempre es
  `templates/pipeline-reference.md` (~650 palabras, instrucciones globales de
  opencode); conviene revisarlo con el mismo criterio. Los `commands/*.sh` no pesan
  por sesión: su salida solo se lee cuando el comando corre.
- **A/B (separar):** el equivalente sería un `install.sh --docs-only` o un segundo
  repo para los `/doc-*`. Hoy no hace falta: no hay costo por descripción que ahorrar.
  Separar solo tendría sentido si el registro se usa sin el pipeline.

Esfuerzo: C restante (pipeline-reference.md) **S** · A/B **M**.

### Anexo — consolidar la familia de docs

Este cambio sí aplica a open-sdd y rompe cosas:

| Paso en sdd-plugin | Par en open-sdd | Qué toca |
|---|---|---|
| 1. Consolidar en `ask` | Crear `/doc-ask` (`commands/doc-ask.sh`) que consulte los cuatro registros, con el índice de topics/colas y la detección del servicio objetivo que hoy tiene `doc-catalog-query.sh` | Comando nuevo: `install.sh`, conteo del README, `check-install-parity.sh` |
| 2. Quitar los `*-query` | Quitar `doc-catalog-query`, `doc-adr-query`, `doc-spec-query` y `doc-investigation-query`, y dejar stubs una versión | `tests/check-sdd-surface-parity.sh` **exige hoy los 8 comandos doc**: hay que cambiar esa regla. Requiere OK, porque borra comandos |
| 3. Separar el registro | Opcional (ver arriba) | — |

Riesgo propio de open-sdd: `lib/service-name.sh` y el `service-name.sh` de
sdd-plugin derivan la clave del servicio por separado. Si el registro se comparte
entre los dos (`$OPEN_SDD_DOC_HOME` = `$CLAUDE_DOC_HOME`), deben derivar la misma
clave; si no, los specs y ADR de un mismo servicio terminan en carpetas distintas.
Antes del paso 1 conviene agregar un test de paridad entre ambos.

---

## 5. Specs que sobreviven a la feature (recomendada: B)

Aplica igual. open-sdd ya tiene los ids `B<n>`, la conformidad y la promoción de
reglas (parity C1).

- **Tags con slug** (`spec: <slug>#B3`, que sigue aceptando `spec: B3`): cambiar
  `_TAG` en `engine/conformance.py`, las instrucciones de `commands/implement.sh` y
  `tests/test_conformance.py`.
- **Aviso en `/f-close`** cuando el spec no se publicó: el lugar es `commands/close.sh`,
  antes del pase de promoción. Ojo: `close.sh` no consulta el estado del MR (la
  versión de sdd-plugin sí), así que el aviso solo puede revisar el archivo, no el
  merge.
- **Doc:** `docs/concepts.md` debería decir que `spec.md` es un contrato de cambio
  y que lo durable vive en `.claude/rules/` (promovidas) y en el registro.

Esfuerzo: **S**.

---

## 6. Review en dos etapas (recomendada: B, con C opcional)

Aplica, con una diferencia de mecanismo. En open-sdd el auditor no lanza
subagentes: `commit.sh` pide `/f-code-review --auditor` y el agente hace la review
en la misma sesión (parity C2).

- **Etapa 1 (spec ↔ diff por Behavior):** nuevo modo `code-review.sh --spec-audit`.
  Imprime el spec y el diff (misma ref que el auditor) con instrucciones para
  marcar cada `B<n>` como cumple / no cumple / no verificable, citando la línea.
  Si algún Behavior no cumple, no se pide la etapa 2.
- **Recibo de dos etapas:** `engine/audit.py` guarda hoy un solo veredicto por
  fingerprint. Para dos etapas necesita `stage` o dos campos de veredicto, y
  `audit-required` debe saber qué etapa falta.
- **Costo:** igual que en sdd-plugin en tokens de diff + spec, pero sin overhead de
  subagentes: corre en el contexto de la sesión, que ya tiene el diff cargado.
- **C (opt-in para otros tiers):** un flag en `state.json` que lea `audit-required`.

Esfuerzo: B **M** · C **S** sobre B.

---

## Hallazgos de la paridad que no están en las propuestas

- **`/f-commit` sin pipeline y en modo no interactivo fallaba:** escribía el
  mensaje en `.specwork/_state/<slug>-commit-msg.txt`, y sin pipeline ese
  directorio no existe. Ya existía antes de la paridad. **Corregido:** sin
  `.specwork/_state/` usa un archivo temporal y no crea `.specwork/`.
- **Dos implementaciones de triage:** `commands/triage.sh` (la que usa `/f-spec`) y
  `engine/cli.py::triage` (solo la usan los tests). Divergen: en `triage.sh` focused
  es `LOW` y en la otra `MEDIUM`, y solo la primera escribe `skip`. El override de
  nivel se implementó en `triage.sh`. Conviene borrar la copia del engine o hacer
  que `triage.sh` la llame.
- **Los `.html` de `docs/presentation/` son renders (Marp) de los `.md`:** se
  corrigieron los `.md`, pero hay que regenerar los `.html`; todavía citan
  `/doc-publish`, `/doc-query` y `/adr-query`.
