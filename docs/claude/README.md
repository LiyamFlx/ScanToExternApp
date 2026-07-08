# ScanToExternApp v5.0 — Reference Docs Index

These files hold the detailed reference material that used to live inside the monolithic `CLAUDE.md` (originally ~53 KB). `CLAUDE.md` is now a tight rules-only sheet; everything below is **verbatim** content moved out of it, read on demand.

Nothing was deleted in the split — every line of the original either stays in `CLAUDE.md` (tightened) or lives verbatim in one of these files.

## Files

| File | Verbatim content moved here | Read when |
|------|-----------------------------|-----------|
| `architecture.md` | Project Overview, Hard Technical Decisions (Mac + Windows tables), Project Structure tree, Full Scan Pipeline data-flow diagram, Info.plist Requirements, Scanmarker BLE Protocol, Platform Support Summary, original build-prompt header | Designing a component; checking a framework/library choice; hardware protocol details |
| `build-phases.md` | Build Order + Phases 1–8 (macOS), all step-by-step code, and the Starter Commands bootstrap block | Implementing a Mac phase; copying the exact code sketches |
| `build-phases-windows.md` | Phase 9 (Windows / Tauri + Rust), all step-by-step code | Implementing the Windows app |
| `constraints.md` | Security Hardening Checklist + "What NOT to Build" list | Verifying you're not violating a hard constraint |
| `acceptance-criteria.md` | Acceptance Criteria (Sprints 1–4) + Testing Plan | Defining "done"; writing tests |

## How to use

- Start each session from `../CLAUDE.md` (small, loads fast).
- When you need specifics, open the one file above that covers it — don't paste the whole spec.
- These files are referenced as plain paths in `CLAUDE.md`, **not** `@`-imports, so they are not auto-loaded into context.

_Split performed 2026-07-08. Source of truth for the pre-split original: git history (`git show <pre-split-commit>:CLAUDE.md`)._
