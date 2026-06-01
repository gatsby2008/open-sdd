# Docs Parity Checklist

Use this checklist whenever behavior changes in `open-sdd` or `claude-tools/sdd`.

## Required updates

- Update command behavior docs (`README`, cheatsheets, skill/flow docs).
- Update artifact contract docs (`specwork-artifacts.md`) if files/folders changed.
- Update parity comparison docs (`why-open-sdd.md`, parity-gap notes) when claims change.
- Update recovery/non-interactive sections when gate behavior changes.
- Update command counts or test counts if quoted as exact numbers.

## Verification pass

- Confirm links resolve (relative links from each edited file).
- Confirm examples/flags match actual command behavior.
- Confirm no mixed-language sections unless intentionally bilingual.
- Confirm no duplicated source-of-truth sections (prefer link to canonical doc).

## Sync targets

- `open-sdd/docs/learning/*`
- `claude-tools/contrib/skills/sdd/learning/*`

If one side changes and the other does not, add a note in the parity-gap doc.
