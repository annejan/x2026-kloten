# CLAUDE.md

This project uses a tool-neutral onboarding doc — see
[`AGENTS.md`](./AGENTS.md) for everything Claude (Code, Sonnet, Opus
or otherwise) needs to know to get useful in this codebase: build
pipeline, memory layout, VICE-MCP debugging workflow, recurring
KickAssembler / Spindle / VIC gotchas, project tone, and pending
work.

The deeper guides live under [`docs/`](./docs/):

- [`docs/sound-arc.md`](./docs/sound-arc.md) — how music flows from
  intro's resident tables through interlude / greets into end, and
  the SID-volume + filter-mode pitfalls that come with that design.
- [`docs/pefchain-notes.md`](./docs/pefchain-notes.md) — Spindle 3.1
  specifics: EFO header tags, transition conditions, segment-size
  traps, load-gap analysis.
- [`docs/sid-drums.md`](./docs/sid-drums.md) — classic SID percussion
  techniques (pitched kick, noise+pulse layering, snare, hat, voice-
  sharing patterns) and how we apply them in greets.

If you're updating long-form guidance, prefer editing those files
over creating new top-level docs.
