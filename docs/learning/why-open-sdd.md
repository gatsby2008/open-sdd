# Why open-sdd?

A short justification for using bash-first tooling instead of letting the LLM drive file I/O directly.

## The core insight

Every operation that touches the filesystem — grep, find, cat, stat, diff — costs tokens when the LLM does it. It also costs time, because each tool call is a round-trip through the model. And it costs reliability, because LLMs hallucinate paths, miss matches, and produce different results across sessions.

open-sdd moves all filesystem work to local bash scripts. The LLM never calls grep, never reads raw source files, never parses directory trees. It receives only structured, pre-filtered output.

| Task | Without open-sdd | With open-sdd |
|------|------------------|---------------|
| Find all REST endpoints in a Java project | LLM greps `@RequestMapping`, reads files, guesses paths — 10-50 tool calls, 5K-50K tokens | `bash doc-catalog.sh` — zero tokens, 0.2s |
| Check if docs are stale vs code | LLM reads index.md, then each referenced doc, then checks git log — 15+ tool calls | `bash doc-freshness.sh` — zero tokens, 0.5s |
| Publish service catalog to registry | LLM reads filesystem, echoes content, relies on user to copy | `bash doc-publish.sh --with-docs` — zero tokens, 0.3s |
| Query "what high gaps are open?" | LLM reads product-spec.md + gap-analysis.md (600+ lines), parses tables | `bash spec-query.sh` → LLM answers from 3 printed docs — 1 tool call, predictable context |
| Detect drift in a new project | LLM explores directory tree, greps for version strings, compares dates — unbounded | `bash doc-freshness.sh <path>` — zero tokens, deterministic output |

## Token efficiency

The most expensive LLM operation is exploration. When a model needs to find something but doesn't know where it is, it fires serial tool calls until it converges. Each failed attempt burns the full cost of a request.

open-sdd scripts are **deterministic one-shot operations**:

```bash
# Without open-sdd: LLM makes 5-20 tool calls to build a mental model of the project
# With open-sdd: one bash invocation
bash doc-catalog.sh
# Output: all endpoints, integrations, config in 50 lines
```

The LLM receives exactly what it needs — no more, no less. The cost is predictable because the input size is bounded by the script's output, not by the size of the codebase.

## Determinism

The same script on the same repo produces the same output every time. Two LLM sessions on the same codebase produce different grep results — different regex interpretations, different file choices, different summarization.

Determinism matters for:
- **CI pipelines** — scripts can be part of automated checks
- **Team consistency** — everyone gets the same answer to "what endpoints exist?"
- **Audit** — a script's output is reproducible; an LLM's "scan" is not

## Zero hallucination in metadata

LLMs hallucinate file paths, class names, and endpoint signatures. A bash script using `grep -rn '@RequestMapping' src/` returns exactly what exists — no invented controllers, no guessed URLs.

The LLM's job is limited to **semantic reasoning** over verified data: "given these endpoints, which ones are missing role-based auth?" That is what LLMs are good at. Finding endpoints is not what LLMs are good at.

## Cross-session caching

Every script output is deterministic and can be cached. The registry (`$OPEN_SDD_DOC_HOME`) acts as a cross-session, cross-service cache:

```bash
/doc-publish --with-docs   # writes to registry once
/doc-query "..."           # reads registry, same result every time
/spec-query "..."          # reads registry, no re-scan needed
```

Without open-sdd, every new LLM session re-discovers the same information — the same grep, the same file reads, the same token burn.

## Offline capability

Scripts run 100% locally. No API call, no model inference, no internet:

```bash
bash doc-catalog.sh     # works offline
bash doc-freshness.sh   # works offline
bash doc-publish.sh     # works offline
```

The LLM is only needed when you want a natural-language answer. The data collection, filtering, and publishing all happen on your machine with zero cloud dependency.

## LLM-agnostic

Scripts don't care which model drives them. They work with:

- opencode
- Claude Code
- GitHub Copilot
- Gemini Code Assist
- Ollama (local models)
- Any tool that can run `bash script.sh`

No prompt engineering, no model-specific format, no vendor lock-in.

## Summary

| Property | open-sdd | LLM-driven |
|----------|----------|------------|
| File I/O cost | 0 tokens | 5K-50K tokens per task |
| Output | Deterministic | Probabilistic |
| Hallucination risk | Zero | High (paths, classes, versions) |
| Cross-session reuse | Registry cache | Starts from zero |
| Offline | Yes | No |
| Model-agnostic | Yes | Tied to one model |
| Per-task consistency | Identical across runs | Varies by session |
| Team collaboration | Shared registry | Each dev re-discovers |
