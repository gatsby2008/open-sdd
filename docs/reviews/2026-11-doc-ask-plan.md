# Plan — `/doc-ask`: una consulta para los cuatro registros

Reemplaza `doc-catalog-query`, `doc-adr-query`, `doc-spec-query` y
`doc-investigation-query`. Par en sdd-plugin: `/sdd:ask`. `arch-query` ya se
eliminó (no forma parte de esto).

## Por qué

- Cuatro comandos que el usuario o el agente tiene que elegir.
- `doc-catalog-query` y `doc-spec-query` imprimen el registro entero. En el
  registro real del equipo eso es ~568 KB de catálogos (~140k tokens) por
  pregunta: la "Selective Context Retrieval" no se cumplía.
- La lógica de acotar por servicio estaba duplicada en bash y sin tests.

## Diseño

```
/doc-ask <pregunta> [type:catalog|adr|spec|investigation] [service:<nombre>]
```

La lógica vive en `engine/registry.py` (`engine.cli ask`); `commands/doc-ask.sh`
solo la llama.

1. **Alcance.** `type:` filtra registros (sin él: los cuatro). Solo `service:`
   explícito filtra por servicio. Un servicio nombrado en la pregunta **sube**
   el puntaje de sus documentos pero no filtra: "¿quién consume X de
   leads-service?" necesita los catálogos de los *otros* servicios.
2. **Índice.** Siempre se imprime: una línea por documento (registro, ruta,
   título, fecha). Es la red de seguridad cuando la búsqueda falla (sinónimos,
   pregunta en castellano y docs en inglés): el agente elige por título y lee.
3. **Búsqueda.** Términos de la pregunta (identificadores primero, sin
   stopwords en/es). Ranking por términos distintos, con bonus en título y
   encabezados.
4. **Carga selectiva.** Archivos mejor rankeados hasta un presupuesto
   (`OPEN_SDD_ASK_BUDGET`, default 60 000 caracteres). Un archivo grande se
   recorta a su encabezado y las secciones `##` que coinciden; las omitidas se
   listan. Si todo el alcance entra en el presupuesto, se imprime todo.
5. **Pistas por tipo** al modelo: cadenas publish→consume (catalog), supersedes
   (adr), Open Questions (spec), orden cronológico (investigation).
6. **Filtro estructural** para "specs con open questions": carga solo las
   `- [ ] **#N**` sin resolver.

### `type:` es un atajo, no un requisito

Los agentes no lo agregan de forma confiable, y no hace falta: sin `type:` la
respuesta tiene que ser igual de buena. El parser tolera variantes (`type: adr`,
`--type adr`, alias `adrs`/`specs`/`catalogo`/`investigaciones`); un tipo
desconocido avisa y se ignora. Cuando ≥80 % de las coincidencias caen en un
registro, la salida sugiere el `type:` correspondiente. El código del pipeline
usa flags (`--type`, `--service`), no texto libre.

## Fases (un commit cada una, sin push salvo pedido)

| # | Fase | Estado |
|---|---|---|
| 0 | Test de paridad del resolver de servicio con sdd-plugin (`tests/test_service_name.py`) | hecho |
| 1 | `engine/registry.py` + `engine.cli ask` + `tests/test_registry.py` | hecho |
| 2 | `commands/doc-ask.sh`, registro en `install.sh`/`install.ps1`, smoke | |
| 3 | Los cuatro `*-query` pasan a stubs deprecados que delegan en `doc-ask type:<x>` | |
| 4 | Docs: `pipeline-reference.md` (4 filas → 1), `REFERENCE.md`, `AGENTS.md`, README, learning | |
| 5 | Borrar los stubs (requiere OK): parity check exige `doc-ask`, `install.sh` limpia los `.md` viejos | |
| 6 | Más adelante: navegar la capa `wiki/` si existe y avisar si está atrasada | |

## Medición contra el registro real (2026-11-02, 96 docs, ~980 KB)

| Pregunta | Hoy | `/doc-ask` |
|---|---|---|
| quién consume ApplicationStageChangeEvent? | `doc-catalog-query`: 568 KB | 30 KB; carga los 2 catálogos que lo mencionan, recortados a sus secciones |
| who publishes DealLostEvent and who consumes it | 568 KB | 43 KB; carga el único catálogo que lo menciona |
| por qué migramos a aws sdk v2? | dos comandos (adr + spec) | 79 KB; ADRs y specs de la migración en una consulta |
