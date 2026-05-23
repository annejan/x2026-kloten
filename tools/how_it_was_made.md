# How it was made

*Kloten met de broodtrommel — deFEEST — released at X 2026.*

This is the long-form companion to the `.nfo`'s short note on AI
authorship. We think the scene deserves the full picture.

## The setup

One human (Anus/deFEEST) hadn't touched the breadbin in years. Life
got in the way. In May 2026 he sat down with three large-language-
model AI agents in a tight feedback loop and asked: can we ship a
demo for X2026 in three weeks?

The three AIs:

- **Kloot/deFEEST** — Anthropic Claude (Opus 4.7), via the Claude
  Code CLI tool.
- **Augurk/deFEEST** — OpenCode (the agent-coding tool, internal
  name "Big Pickle").
- **TL-Buis/deFEEST** — OpenAI ChatGPT.

Plus two more humans for direction + reality checks:

- **Ranzbak/deFEEST** — long-time scener; tested raster timing on real
  hardware, contributed FLD-bounce reference code from older deFEEST
  productions.
- **Cinder/deFEEST** — second pair of eyes on audio + pacing.

## What the AIs actually did

The C64 source code is genuine 6502 in KickAssembler 5.25 syntax.
The AIs wrote ~95% of the .asm bytes that ended up in the released
`.d64`. Concretely:

- **Open-border IRQ chain + raster bars** in the intro
- **FLD (Flexible Line Distance) logo bounce** with the late-write
  spurious-badline trick + stable-raster wrapper (Mäkelä /
  JackAsser pattern)
- **Multicolour bitmap scroller** at the top of the intro, three
  modes (left / right / zig-zag) cycling via sentinel chars
- **Text-mode plasma + sprite-letter SPARKED drop** in interlude
- **Dual-axis sine wobble + LP filter close** in hush
- **DYCP sprite-font scroller** in greets, with 16-bit scroll
  position + per-tier wobble damping + KLOOT settle landing
- **Twin Kloot-star quad** in coda — pre-rendered 24-frame zoom
  sequences with ping-pong breath, sine-orbit motion, alternating
  in-front/behind-text priority swap, 32-star 4-tier parallax
  PETSCII starfield
- **3-voice resident SID engine** with K-S-K-S drum kit + V1
  bass-bleed sub-thump, inherited from intro through every
  subsequent part via Spindle's `'I'` page-claim mechanism
- **Sweeping V3 PWM + LP filter end-credits LFO** modulating
  between clean and dark moods on a slow ~20 s cycle

## What the humans did

- **Picked what to build.** Every effect, every text line, every
  audio sweep is a human aesthetic decision. The AIs proposed
  and implemented; the humans accepted, rejected, or asked for
  variants until something landed.
- **Listened.** Music decisions ("more belly punch than head
  punch", "the kick is killing the arpeggios", "we might want
  to modulate between dark and clean") were entirely human.
- **Caught the bugs the AIs couldn't see.** ZP slot collisions
  silently muting the SID, sprite Y-register stride bugs scattering
  DYCP wobble, self-modifying-code that patched the opcode instead
  of the operand — humans noticed these on screen and pointed
  them out for the AIs to fix.
- **Decided when to stop.** "Sounds good for now", "ship it",
  "no PR needed, just push" — there's no algorithm for those.

## The development loop

The killer technology was **VICE-MCP**: a build of VICE x64sc with
an embedded MCP (Model Context Protocol) server exposing ~70
debugging tools over JSON-RPC at `127.0.0.1:6510`. From the AI's
perspective, the running emulator was a REPL it could poke:

- `vice.display.screenshot` to see what was on screen
- `vice.registers.get` to read the 6510 state
- `vice.memory.read` to see exactly which 12 bytes got corrupted
- `vice.vicii.get_state` to dump every VIC register
- `vice.sid.get_state` to inspect SID voices + filter + master vol
- `vice.checkpoint.add` for breakpoints

The loop looked like:

1. **Human asks for an effect** ("I want the brown star to zoom in
   and the cyan one to zoom out, naturally out of phase")
2. **AI proposes a design**, often referencing
   [codebase.c64.org](https://codebase.c64.org/) for the canonical
   technique
3. **AI edits the `.asm`**, runs `./build.sh`, autostarts in
   VICE-MCP
4. **AI screenshots the result**, reads memory if anything looks
   wrong
5. **Human watches**, either accepts ("perfect for now") or
   redirects ("this is glitched as fuck with the letters popping
   in")
6. **AI commits and pushes**

Roughly 180 commits over three weeks. The git log IS the design
journal — every decision is there with its reasoning in the
commit message.

## What we learned

- **The AIs are good at the implementation grind.** Writing
  KickAssembler 6502 from a clear specification is squarely in
  the LLM sweet spot. Cycle counting, IRQ chain construction,
  page-aligned table layout, ZP allocation — all bread-and-butter.

- **The AIs are bad at music aesthetics.** They'll write a kick
  drum that's technically correct (right pitch sweep, right
  envelope, right SID register pokes), but whether it "lands"
  is something only a human listening can judge. Same for
  visual pacing — when does SPARKED land, how long does KLOOT
  hold, when does the fade kick in. Humans drove every one.

- **The AIs are bad at remembering the codebase across
  sessions.** Without project-specific memory + a curated
  `AGENTS.md` doc + persistent committed docs, every fresh
  AI conversation starts from zero. We invested heavily in
  documentation specifically so AI helpers stay grounded
  between sessions.

- **The AIs are bad at catching their own bugs.** Self-modifying
  code that overwrites its own opcode, multi-line typewriter
  reveals that block until a flag flips, ZP slot collisions
  that silently mute the SID — these all required a human
  noticing and pointing at the screen.

- **The AIs cooperate well across vendors.** Kloot (Claude),
  Augurk (OpenCode), and TL-Buis (ChatGPT) routinely
  collaborated through GitHub PRs — one would open a feature
  PR, another would review, the human would merge. The agents
  don't "know" they're different vendors; they just see the
  codebase + commit log.

## The bigger picture

This is the first deFEEST release where most of the actual code
came from AI agents rather than from human pair-coders. It's
2026 — we expect this to become normal in the scene over the
next year or two. We wanted to be early and honest about it
rather than late and coy.

If you want to look under the hood:

- Repository: [github.com/annejan/outline26-claude-c64](https://github.com/annejan/outline26-claude-c64)
- The full commit log shows every decision and its rationale
- `AGENTS.md` is the onboarding doc the AIs read first
- `docs/` has long-form guides for sound, narrative, memory
  layout, pefchain, SID drums, IRQ timing
- `docs/two-weeks-out.md` is a snapshot reflection from late
  in the sprint

If something in the release surprises you — good or bad — drop
us a note. We'd love to hear how it lands.

— deFEEST / 2026
