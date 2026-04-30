# Architecture

> Read by `@tech-lead`. Fill in the sections that apply; leave others blank.

## Stack

List the primary language(s), frameworks, and data stores used.

## Rules

- Files > 500 LOC need a documented split rationale
- No circular imports between domain packages
- Every new top-level dependency needs an ADR in docs/adr/

## Known tech debt (accepted)

List tech debt items that are accepted and tracked, to prevent noise in audits.

<!-- - Legacy auth module (src/auth-v1/) — migration tracked in #44 -->

## ADR directory

Path to architecture decision records (default: `docs/adr/`).
