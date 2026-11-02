"""Selective retrieval over the doc registries — the logic behind /doc-ask.

One query reads the four registries written by /doc-catalog, /doc-adr, /doc-spec
(/f-mr) and /doc-investigation and prints, for the model to answer from:

  1. an INDEX of every in-scope document (always — the fallback when term search
     misses, e.g. a Spanish question over English docs);
  2. the best-ranked documents in full, or trimmed to their matching `##`
     sections when large, up to a character budget;
  3. the other matches by path, so the model can read them on demand;
  4. per-registry reading hints;
  5. when a compiled `wiki/` layer sits next to the registry root (a two-layer
     vault: OPEN_SDD_DOC_HOME = <vault>/raw), its location and whether it lags
     the raw docs (changed after the last `wiki/log.md` entry).

`type:` and `service:` narrow the scope but are never required: a question with
no filters must still land on the right documents. A service named in the
question boosts its documents instead of filtering, because cross-service
questions ("who consumes X from leads-service?") need the other services.
"""
from __future__ import annotations

import math
import subprocess
import os
import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Optional

# type -> registry directory, in output order.
REGISTRIES = {
    "catalog": "service-catalog",
    "adr": "adr-registry",
    "spec": "spec-registry",
    "investigation": "investigation-registry",
}

TYPE_ALIASES = {
    "catalog": "catalog", "catalogs": "catalog", "catalogo": "catalog",
    "catalogos": "catalog", "catálogo": "catalog", "catálogos": "catalog",
    "service-catalog": "catalog",
    "adr": "adr", "adrs": "adr", "decision": "adr", "decisions": "adr",
    "decision-records": "adr", "adr-registry": "adr",
    "spec": "spec", "specs": "spec", "spec-registry": "spec",
    "investigation": "investigation", "investigations": "investigation",
    "investigacion": "investigation", "investigaciones": "investigation",
    "investigación": "investigation", "inv": "investigation",
    "investigation-registry": "investigation",
}

# Words that say which kind of document the question wants. They boost that
# registry (never filter) and are dropped from the search terms, since a word
# like "spec" appears in half the registry.
KIND_WORDS = {
    "spec": "spec", "specs": "spec", "especificacion": "spec", "especificaciones": "spec",
    "adr": "adr", "adrs": "adr", "decision": "adr", "decisions": "adr",
    "decisiones": "adr",
    "investigation": "investigation", "investigations": "investigation",
    "investigacion": "investigation", "investigaciones": "investigation",
    "catalog": "catalog", "catalogs": "catalog", "catalogo": "catalog",
    "catalogos": "catalog",
}
KIND_BOOST = 1.5

HINTS = {
    "catalog": "Catalogs: follow Publishes -> topic/queue -> Consumes across services "
               "to chain event flows; Endpoints tables answer who-calls-what.",
    "adr": "ADRs: answer from Context + Decision; follow Supersedes/Superseded-by "
           "chains and say which decision is current.",
    "spec": "Specs: Behavior and Scope describe the feature; Safe Constraints bound "
            "changes; '- [ ]' Open Questions are unresolved.",
    "investigation": "Investigations are listed oldest first: for 'have we seen this "
                     "before?' tell the history in order (bug / exploration / improvements).",
}

CATALOG_MAX_AGE_DAYS = 90       # older catalogs get a freshness warning (OPEN_SDD_CATALOG_MAX_AGE_DAYS)
_VERIFIED_AT = re.compile(r"Verified at:\s*`?([0-9a-f]{7,40})`?")
DEFAULT_BUDGET = 60_000          # characters printed for loaded documents
TRIM_THRESHOLD = 12_000          # docs larger than this print matching sections only
PREAMBLE_CAP = 1_500             # chars kept from a trimmed doc's header
RELATIVE_CUTOFF = 0.25           # load only matches scoring >= 25% of the best

STOPWORDS = set("""
a about above after again all also an and any are as at be because been before
being between both but by can could did do does doing done down during each
every few for from had has have having he her here hers how i if in into is it
its just me more most my no nor not now of off on once only or other our out
over own same she should so some such than that the their them then there these
they this those through to too under until up very was we were what when where
which while who whom why will with would you your across ever seen tell show
list find give know need please there's what's who's
el la los las un una unos unas de del al a ante bajo con contra desde en entre
hacia hasta para por segun sin sobre tras y o u e ni que quien quienes cual
cuales como cuando donde cuanto es son ser fue fueron era eran esta estan este
esto estos estas ese esa esos esas eso hay se su sus lo le les me mi mis te tu
tus nos ya no si sí mas más muy tambien también alguna alguno algun algún vez
veces todos todas todo toda cada qué cómo cuál dónde por qué porque tenemos
tiene tienen hace hacen sido hemos han visto antes dame decime mostrame
""".split())

_TOKEN = re.compile(r"/?[\w{}][\w./{}:-]*", re.UNICODE)
# `type:adr`, `type: adr`, `--type adr`, `--type=adr` (same for service). A bare
# "type of" in prose is not a filter.
_FILTER = re.compile(r"(?:^|\s)(?:--(type|service)(?:=|\s+)|(type|service):\s*)([\w.,-]+)", re.I)
_OQ_INTENT = re.compile(r"open[ -]?questions?|preguntas? abiertas?|\boqs?\b", re.I)
_UNRESOLVED_OQ = re.compile(r"^\s*- \[ \] \*\*#\d+\*\*")
_ISO_DATE = re.compile(r"(\d{4}-\d{2}-\d{2})")


@dataclass
class Query:
    text: str
    types: list[str]
    service: Optional[str]
    warnings: list[str] = field(default_factory=list)
    explicit_types: bool = False


@dataclass
class Doc:
    kind: str
    rel: str            # path relative to the registry root, e.g. adr-registry/x/y.md
    path: Path
    service: str
    title: str
    date: str
    text: str
    score: float = 0.0


# ---------------------------------------------------------------- parsing ---

def parse_query(args: list[str]) -> Query:
    """Split filters (`type:adr`, `type: adr`, `--type adr`, `service:x`) from the
    question. Unknown types warn and are ignored — agents improvise syntax."""
    raw = " ".join(args)
    types: list[str] = []
    service: Optional[str] = None
    warnings: list[str] = []

    def take(m: re.Match) -> str:
        nonlocal service
        key, val = (m.group(1) or m.group(2)).lower(), m.group(3).strip(",")
        if key == "service":
            service = val.lower()
        else:
            for part in val.lower().split(","):
                canon = TYPE_ALIASES.get(part)
                if canon:
                    if canon not in types:
                        types.append(canon)
                else:
                    warnings.append(f"unknown type '{part}' ignored "
                                    f"(valid: {', '.join(REGISTRIES)})")
        return " "

    text = _FILTER.sub(take, raw).strip()
    ordered = [t for t in REGISTRIES if t in types]
    return Query(text=text, types=ordered or list(REGISTRIES), service=service,
                 warnings=warnings, explicit_types=bool(ordered))


def _fold(word: str) -> str:
    """Lowercase and drop accents, so 'quién' matches the stopword 'quien'."""
    return "".join(c for c in unicodedata.normalize("NFD", word.lower())
                   if unicodedata.category(c) != "Mn")


def _stem(word: str) -> str:
    """Crude, language-agnostic stem for plain words, matched as a substring:
    drop an English '-es' after sh/ch/x/z/ss ('pushes' -> 'push') or a plural
    's'; then cut long words to a prefix so derivations meet across languages
    ('duplicados'/'duplicate' -> 'duplic', 'decisiones'/'decision' -> 'decisi')."""
    if len(word) > 4 and word.endswith("es") and word[:-2].endswith(("sh", "ch", "x", "z", "ss")):
        word = word[:-2]
    elif len(word) > 4 and word.endswith("s") and not word.endswith("ss"):
        word = word[:-1]
    if len(word) >= 8:
        word = word[:max(6, len(word) - 3)]
    return word


def kind_intent(text: str) -> set[str]:
    """Registries the question names ('which specs…', 'decisiones sobre…')."""
    return {KIND_WORDS[_fold(w)] for w in re.findall(r"[\w]+", text) if _fold(w) in KIND_WORDS}


def extract_terms(text: str) -> list[tuple[str, bool]]:
    """Return (term, is_identifier) pairs, lowercased and de-duplicated.
    Identifiers (CamelCase, kebab/snake, paths, digits) are kept verbatim;
    plain words drop stopwords, short words and a trailing plural 's'."""
    seen: dict[str, bool] = {}
    for tok in _TOKEN.findall(text):
        tok = tok.strip(".:,;!?¿¡\"'`()[]")
        if not tok:
            continue
        ident = (bool(re.search(r"[a-z][A-Z]|[A-Z]{2,}[a-z]", tok))
                 or bool(re.search(r"[-_/.]", tok)) or bool(re.search(r"\d", tok)))
        low = tok.lower()
        if not ident:
            if _fold(low) in STOPWORDS or _fold(low) in KIND_WORDS or len(low) < 3:
                continue
            low = _stem(low)
        if low not in seen:
            seen[low] = ident
    return list(seen.items())


# ---------------------------------------------------------------- loading ---

def registry_root() -> Path:
    home = os.environ.get("OPEN_SDD_DOC_HOME")
    if home:
        return Path(home)
    base = os.environ.get("OPEN_SDD_ROOT") or os.environ.get("HOME", "~")
    return Path(base) / ".opensdd" / "registry"


def wiki_status(root: Path, docs: list["Doc"]) -> Optional[tuple[Path, str, list["Doc"]]]:
    """(wiki dir, last ingest date, raw docs modified after it) when a compiled
    `wiki/` layer is a sibling of the registry root; None otherwise. The
    watermark is the newest `## [YYYY-MM-DD]` entry of wiki/log.md."""
    wiki = root.parent / "wiki"
    if not wiki.is_dir():
        return None
    log = wiki / "log.md"
    stamps = re.findall(r"^## \[(\d{4}-\d{2}-\d{2})\]", log.read_text(errors="replace"),
                        re.M) if log.is_file() else []
    if not stamps:
        return wiki, "never", list(docs)
    mark = max(stamps)
    newer = [d for d in docs
             if date.fromtimestamp(d.path.stat().st_mtime).isoformat() > mark]
    return wiki, mark, newer


def _frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    meta = {}
    for line in text[3:end].splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip().lower()] = v.strip().strip("'\"")
    return meta


def _title(text: str, meta: dict[str, str], stem: str) -> str:
    if meta.get("title"):
        return meta["title"]
    for line in text.splitlines():
        if line.startswith("# "):
            return re.sub(r"^Service:\s*", "", line[2:].strip(), flags=re.I)
    return stem


def _date(text: str, meta: dict[str, str], path: Path) -> str:
    for key in ("date", "updated", "last_updated"):
        m = _ISO_DATE.search(meta.get(key, ""))
        if m:
            return m.group(1)
    m = re.search(r"Last updated:\s*(\d{4}-\d{2}-\d{2})", text[:600])
    if m:
        return m.group(1)
    m = _ISO_DATE.match(path.name)
    if m:
        return m.group(1)
    return date.fromtimestamp(path.stat().st_mtime).isoformat()


def _service(kind: str, parts: tuple[str, ...]) -> str:
    # catalog: service-catalog/<svc>.md or service-catalog/docs/<svc>/x.md;
    # the rest: <registry>/<svc>/x.md
    if kind == "catalog":
        if parts[0] == "docs" and len(parts) > 2:
            return parts[1]
        return Path(parts[0]).stem if len(parts) == 1 else parts[0]
    return parts[0] if len(parts) > 1 else "-"


def load_docs(root: Path, types: list[str]) -> list[Doc]:
    docs = []
    for kind in types:
        base = root / REGISTRIES[kind]
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.md")):
            parts = path.relative_to(base).parts
            if any(p.startswith(".") or p == "templates" for p in parts):
                continue
            if kind == "spec" and not path.name.endswith("-spec.md"):
                continue
            text = path.read_text(errors="replace")
            meta = _frontmatter(text)
            docs.append(Doc(
                kind=kind, rel=str(path.relative_to(root)), path=path,
                service=_service(kind, parts).lower(),
                title=_title(text, meta, path.stem), date=_date(text, meta, path),
                text=text,
            ))
    return docs


# -------------------------------------------------------------- freshness ---

def verified_at(text: str) -> Optional[str]:
    """Commit a catalog was generated against (`Verified at: <sha>` in its header)."""
    m = _VERIFIED_AT.search(text[:1500])
    return m.group(1) if m else None


def _git(args: list[str], cwd: str) -> Optional[str]:
    try:
        out = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    except OSError:
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def _is_code(path: str) -> bool:
    low = path.lower()
    return not (low.endswith((".md", ".txt")) or low.startswith(("docs/", ".")) or
                "/test/" in low or "/tests/" in low or low.startswith(("test/", "tests/")))


def catalog_freshness(catalog: Path, repo: str = ".") -> str:
    """How far the service repo at `repo` moved since its catalog was verified."""
    sha = verified_at(catalog.read_text(errors="replace"))
    if not sha:
        return ("not tracked — the catalog has no 'Verified at' commit; regenerate it "
                "with /doc-catalog to start tracking")
    if _git(["cat-file", "-e", f"{sha}^{{commit}}"], repo) is None:
        return (f"verified at {sha}, which is not in this repo's history (rebased, or "
                "generated from another clone) — regenerate with /doc-catalog")
    count = int(_git(["rev-list", "--count", f"{sha}..HEAD"], repo) or 0)
    if count == 0:
        return f"up to date — verified at {sha}, which is HEAD"
    changed = [f for f in (_git(["diff", "--name-only", sha, "HEAD"], repo) or "").splitlines()
               if _is_code(f)]
    msg = f"{count} commit(s) since it was verified at {sha}; {len(changed)} code file(s) changed"
    if changed:
        msg += ": " + ", ".join(changed[:5]) + (" …" if len(changed) > 5 else "")
        msg += f" — regenerate with /doc-catalog if endpoints, events or integrations changed"
    return msg


def _age_days(iso: str) -> Optional[int]:
    try:
        return (date.today() - date.fromisoformat(iso)).days
    except ValueError:
        return None


# ---------------------------------------------------------------- ranking ---

def _headings(text: str) -> str:
    return "\n".join(l for l in text.splitlines() if l.startswith("#")).lower()


def score_docs(docs: list[Doc], terms: list[tuple[str, bool]],
               mentioned: set[str], kinds: frozenset = frozenset()) -> None:
    """IDF-weighted distinct-term score: a term present in every document adds
    little; identifiers weigh double; title/heading hits get a bonus; documents
    of a service named in the question get a boost."""
    if not docs:
        return
    n = len(docs)
    lows = [d.text.lower() for d in docs]
    heads = [_headings(d.text) + "\n" + d.title.lower() + "\n" + d.rel.lower() for d in docs]
    for term, ident in terms:
        df = sum(1 for t in lows if term in t)
        if df == 0:
            continue
        idf = math.log(1 + n / df) * (2.0 if ident else 1.0)
        for d, low, head in zip(docs, lows, heads):
            if term in low:
                d.score += idf * (1.5 if term in head else 1.0)
    for d in docs:
        if d.score and d.service in mentioned:
            d.score *= 1.5
        if d.score and d.kind in kinds:
            d.score *= KIND_BOOST


# -------------------------------------------------------------- rendering ---

def _sections(text: str) -> tuple[str, list[tuple[str, str]]]:
    """Split on `## ` headings outside code fences -> (preamble, [(heading, body)])."""
    pre, secs, cur_head, buf, fence = [], [], None, [], False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("```"):
            fence = not fence
        if not fence and line.startswith("## "):
            if cur_head is None:
                pre = buf
            else:
                secs.append((cur_head, "".join(buf)))
            cur_head, buf = line.strip(), [line]
            continue
        buf.append(line)
    if cur_head is None:
        return "".join(buf), []
    secs.append((cur_head, "".join(buf)))
    return "".join(pre), secs


def trim(doc: Doc, terms: list[tuple[str, bool]]) -> str:
    """Full text when small; else header + the `##` sections that match a term,
    listing the omitted ones so the model can ask for them."""
    if len(doc.text) <= TRIM_THRESHOLD:
        return doc.text
    pre, secs = _sections(doc.text)
    if not secs:
        return doc.text
    keep, omitted = [], []
    for head, body in secs:
        low = body.lower()
        (keep if any(t in low for t, _ in terms) else omitted).append((head, body))
    if len(pre) > PREAMBLE_CAP:
        pre = pre[:PREAMBLE_CAP].rsplit("\n", 1)[0] + "\n[... header trimmed ...]\n"
    out = pre + "".join(body for _, body in keep)
    if omitted:
        out += ("\n[omitted sections — read the file for them: "
                + "; ".join(h.lstrip("# ") for h, _ in omitted) + "]\n")
    return out


def _open_questions(doc: Doc) -> str:
    lines = [l for l in doc.text.splitlines() if _UNRESOLVED_OQ.match(l)]
    return ("## Open Questions (unresolved only)\n" + "\n".join(lines) + "\n") if lines else ""


@dataclass
class Result:
    root: Path
    query: Query
    terms: list[tuple[str, bool]]
    scope: list[Doc]
    loaded: list[tuple[Doc, str]]
    also: list[Doc]
    mode: str           # "all" | "ranked" | "open-questions" | "none"


def select(query: Query, docs: list[Doc], budget: int = DEFAULT_BUDGET) -> Result:
    root = registry_root()
    scope = [d for d in docs if not query.service or d.service == query.service]
    terms = extract_terms(query.text)

    if _OQ_INTENT.search(query.text) and "spec" in query.types:
        loaded = [(d, _open_questions(d)) for d in scope if d.kind == "spec"]
        loaded = [(d, body) for d, body in loaded if body]
        return Result(root, query, terms, scope, loaded, [], "open-questions")

    mentioned = {d.service for d in scope if d.service != "-"
                 and re.search(rf"(?<![\w-]){re.escape(d.service)}(?![\w-])",
                               query.text, re.I)}
    score_docs(scope, terms, mentioned, frozenset(kind_intent(query.text)))
    ranked = sorted((d for d in scope if d.score > 0), key=lambda d: -d.score)

    if sum(len(d.text) for d in scope) <= budget:
        rest = [d for d in scope if d.score == 0]
        return Result(root, query, terms, scope,
                      [(d, d.text) for d in ranked + rest], [], "all")
    if not ranked:
        return Result(root, query, terms, scope, [], [], "none")

    floor = ranked[0].score * RELATIVE_CUTOFF
    loaded, also, used = [], [], 0
    for d in ranked:
        body = trim(d, terms)
        if d.score >= floor and (used + len(body) <= budget or not loaded):
            if used + len(body) > budget:            # the best match alone overflows
                body = body[:budget] + "\n[... truncated at budget ...]\n"
            loaded.append((d, body))
            used += len(body)
        else:
            also.append(d)
    return Result(root, query, terms, scope, loaded, also, "ranked")


def _ordered(loaded: list[tuple[Doc, str]]) -> list[tuple[Doc, str]]:
    """Group by registry (fixed order); investigations oldest first."""
    out = []
    for kind in REGISTRIES:
        group = [x for x in loaded if x[0].kind == kind]
        if kind == "investigation":
            group.sort(key=lambda x: x[0].date)
        out.extend(group)
    return out


def render(res: Result) -> str:
    q, out = res.query, []
    scope_desc = ", ".join(q.types) if q.explicit_types else "all registries"
    if q.service:
        scope_desc += f" · service:{q.service}"
    out.append(f"Registry: {res.root}")
    out.append(f"Scope: {scope_desc} · {len(res.scope)} docs · "
               f"terms: {', '.join(t for t, _ in res.terms) or '(none)'}")
    for w in q.warnings:
        out.append(f"warning: {w}")
    out.append("")

    if not res.scope:
        out.append(f"No documents found in {res.root}"
                   + (f" for service '{q.service}'" if q.service else "") + ".")
        out.append("Write them with /doc-catalog, /doc-adr, /doc-spec (or /f-mr) "
                   "and /doc-investigation, then ask again.")
        return "\n".join(out) + "\n"

    wiki = wiki_status(res.root, res.scope)
    if wiki:
        wdir, mark, newer = wiki
        out.append(f"WIKI: {wdir} (last ingest: {mark}) — its [[backlinks]] help with "
                   "cross-cutting questions, but ground every claim in the raw docs.")
        if newer:
            out.append(f"⚠ The wiki is behind: {len(newer)} raw doc(s) in scope changed "
                       "after the last ingest, e.g. "
                       + ", ".join(d.rel for d in newer[:3])
                       + ". Answers below come from the raw docs and are current; "
                       "the wiki's cross-links may miss them until it is re-ingested.")
        out.append("")

    out.append("INDEX")
    for d in sorted(res.scope, key=lambda d: (list(REGISTRIES).index(d.kind), d.rel)):
        out.append(f"  {d.kind:<13} {d.rel}  —  {d.title}  ({d.date})")
    out.append("")

    if res.mode == "open-questions":
        n_specs = sum(d.kind == "spec" for d in res.scope)
        out.append(f"LOADED — unresolved Open Questions only ({len(res.loaded)} of "
                   f"{n_specs} spec(s) have any)")
        if not res.loaded:
            out.append("  none — every spec in scope has its Open Questions resolved.")
    elif res.mode == "all":
        out.append(f"LOADED — whole scope fits the budget ({len(res.loaded)} docs)")
    else:
        out.append(f"LOADED ({len(res.loaded)} docs)")
    if not res.loaded and res.mode != "open-questions":
        out.append("  none — no document matched. Pick candidates from the INDEX by "
                   "title and read them; if nothing fits, say so — never invent.")
    max_age = int(os.environ.get("OPEN_SDD_CATALOG_MAX_AGE_DAYS", CATALOG_MAX_AGE_DAYS))
    for d, body in _ordered(res.loaded):
        sha = verified_at(d.text) if d.kind == "catalog" else None
        out.append("=" * 72)
        out.append(f"FILE: {d.rel}   [{d.kind} · {d.service} · {d.date}"
                   + (f" · verified at {sha}" if sha else "")
                   + (f" · score {d.score:.1f}" if d.score else "") + "]")
        age = _age_days(d.date) if d.kind == "catalog" else None
        if age is not None and age > max_age:
            out.append(f"⚠ This catalog was last regenerated {age} days ago; the service may "
                       f"have changed since. Say so if the answer depends on it "
                       f"(/doc-catalog in that repo refreshes it).")
        out.append("=" * 72)
        out.append(body.rstrip("\n"))
        out.append("")

    if res.also:
        out.append("ALSO MATCHED (not loaded — read with: cat <registry>/<path>)")
        for d in res.also:
            out.append(f"  {d.rel}  [score {d.score:.1f}]")
        out.append("")

    kinds = {d.kind for d, _ in res.loaded}
    hints = [HINTS[k] for k in REGISTRIES if k in kinds]
    if hints:
        out.append("HINTS")
        out.extend(f"  - {h}" for h in hints)
        out.append("")

    matched = [d for d, _ in res.loaded if d.score] + res.also
    if not q.explicit_types and len(matched) >= 3:
        top = max(REGISTRIES, key=lambda k: sum(d.kind == k for d in matched))
        share = sum(d.kind == top for d in matched) / len(matched)
        if share >= 0.8:
            out.append(f"tip: {round(share * 100)}% of matches are in {REGISTRIES[top]}"
                       f" — add type:{top} to narrow.")
            out.append("")

    out.append("---")
    out.append(f"Question: {q.text}")
    out.append("Answer from the documents above. Cite every claim as its path "
               "(e.g. adr-registry/<service>/<file>.md). If an INDEX entry looks "
               "relevant but was not loaded, read it before answering. If the "
               "answer is not in the registry, say what you read — never invent.")
    return "\n".join(out) + "\n"


def ask(args: list[str], budget: Optional[int] = None) -> str:
    query = parse_query(args)
    if budget is None:
        budget = int(os.environ.get("OPEN_SDD_ASK_BUDGET", DEFAULT_BUDGET))
    docs = load_docs(registry_root(), query.types)
    return render(select(query, docs, budget))
