# CLAUDE.md

This project uses a tool-neutral onboarding doc — see
[`AGENTS.md`](./AGENTS.md) for everything Claude (Code, Sonnet, Opus
or otherwise) needs to know to get useful in this codebase: build
pipeline, memory layout, VICE-MCP debugging workflow, recurring
KickAssembler / Spindle / VIC gotchas, project tone, and pending
work.

The deeper guides live under [`docs/`](./docs/):

- [`docs/sound-arc.md`](./docs/sound-arc.md) — how music flows from
  intro's resident tables through interlude / sinus / greets into end, and
  the SID-volume + filter-mode pitfalls that come with that design.
- [`docs/music-theory.md`](./docs/music-theory.md) — the actual theory:
  Aeolian, the i-v-VI-VII loop, voice voicings, ADSR per voice, lead
  phrasing, and the `zp_intro` thresholds that control V3's timbre.
- [`docs/score-baseline.md`](./docs/score-baseline.md) — 2026-05-21
  snapshot of the entire score as it currently plays, with measured
  SID state per part, timing facts, and a list of "more epic" levers
  we could pull. Reach for this when discussing the music with someone
  who knows music, or when planning audio polish.
- [`docs/pefchain-notes.md`](./docs/pefchain-notes.md) — Spindle 3.1
  specifics: EFO header tags, transition conditions, segment-size
  traps, load-gap analysis.
- [`docs/sid-drums.md`](./docs/sid-drums.md) — classic SID percussion
  techniques (pitched kick, noise+pulse layering, snare, hat, voice-
  sharing patterns) and how we apply them in greets.
- [`docs/memory-layout.md`](./docs/memory-layout.md) — the C64 memory
  constraints (VIC banks, chargen ROM hole, $D018 packing) and how
  they shape this demo's per-part layout. Read this before adding a
  new part or moving any data around.
- [`docs/dilemmas.md`](./docs/dilemmas.md) — running log of the design
  trade-offs we've hit, what we tried, and what we chose. Reach for
  this when something "should work" but the trade-off space is
  non-obvious (FLD vs fixed text, IRQ-chain budget, sprite Y-zones,
  pefchain page claims).
- [`docs/intro-architecture.md`](./docs/intro-architecture.md) — the
  intro's live architecture: 5-IRQ chain layout, cycle budgets per
  block, symmetric-FLD wiring + first-write fix + latch pad, music
  split (`my_music_critical` / `my_music_step` / `my_music_play`
  dispatcher at $119e), wishlist for the X2026 sprint.
- [`docs/mcp-debugging.md`](./docs/mcp-debugging.md) — VICE-MCP
  cookbook: 70-tool catalogue, JSON-RPC wrapper gotchas (the `name`
  kwarg collision!), recipes for cycle measurement, IRQ logging,
  conditional auto-snapshot on rare bugs, SID state diffs across
  frames.

If you're updating long-form guidance, prefer editing those files
over creating new top-level docs.
