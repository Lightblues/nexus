---
id: nexus-009
title: Rewrite project spec documentation with changelog and decisions
status: done
priority: low
estimate: M
labels: [docs, spec]
---

## Objective
Rewrite the `.ea/spec/` directory from scratch, splitting the monolithic spec into multiple focused files. Incorporate recent changes (P0/P1 fixes, palette, homebrew) into changelog and document key architectural decisions.

## Context
- `.ea/spec/spec.md` — main architecture spec
- `.ea/spec/` — spec directory (split into multiple files)
- Recent work: IPC leak fix, history archive, shared types, window detection, palette, homebrew

## Tasks
- [x] Split monolithic spec.md into focused sub-documents
- [x] Document changelog with recent modifications
- [x] Record key architectural decisions (shared types approach, hash-based routing, archive strategy, palette design)

## Acceptance
- [x] Spec directory contains multiple focused files instead of one monolith
- [x] Changelog reflects all recent feature and bugfix work
- [x] Decision records exist for major architectural choices
