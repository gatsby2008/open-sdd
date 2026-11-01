# Token Efficiency Checklist (ES)

- Define un `source.md` claro en `/f-start`; evita contexto ambiguo desde el inicio.
- Usa `/f-spec` solo con contexto nuevo; evita refine sin cambios reales.
- Mantén `## Implementation Context` específico (rutas/clases/endpoints concretos).
- Corre `/f-plan` cuando el cambio supera 2–3 archivos (siempre en high-risk); reduce discovery repetido.
- En `/f-implement`, trabaja por pasos pequeños; un objetivo técnico por pasada.
- Evita refactors laterales durante implementación; suben costo sin cerrar alcance.
- Ejecuta `/f-test-design` + `/f-test-impl` solo si dispara el risk gate.
- Antes de reintentar, corrige causa raíz; no hagas loops de “probar por probar”.
- Usa gates determinísticos (`precheck`, OQ, plan obligatorio, staleness, cobertura de tests, risk-signals) como fuente de verdad.
- Si el triage se equivocó de nivel, fuérzalo con `/f-spec --tier <nivel> "<motivo>"` en vez de esquivar los gates.
- Si el diff crece demasiado, divide en commits/lotes antes de seguir generando.
- Si hay bloqueo persistente, escala temprano (`escalations.md`) y corta gasto inútil.
- Cierra ciclo con `commands/check.sh` estable para evitar retrabajo en `/f-mr`.
