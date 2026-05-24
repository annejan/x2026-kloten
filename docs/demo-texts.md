# outline-64 — All on-screen texts

Every piece of text the viewer sees, per part. PETSCII encoded as
screencode_mixed (uppercase `$41-$5A`, lowercase `$01-$1A`, space `$20`).

---

## 1. screenfill — Loading bloom

```
DEFEEST
```

Radial fill bloom pattern expanding across the BASIC screen.

---

## 2. intro — Logo bounce, rasterbars, scroller

Three scroller blocks sequenced via mode switches:

**Block 1** (mode 0, left scroll):

```
 deFEEST presents Anus and Kloot using codebase.c64.org
```

**Block 2** (mode 1, right scroll — played backwards):

```
Open borders, FLD logo, rainbows, 8-sprite balls, custom SID.
```

**Block 3** (mode 2, zig-zag split converging):

```
Greetings to anyone still vibeing the breadbin
```

---

## 3. interlude — Plasma, typewriter, sprite drop

**Line A** (typewriter, row 11):

```
FOR YEARS NO TIME FOR BREADBIN CODE
```

**Line B** (8 sprite letters, drop on bass return):

```
SPARKED
```

---

## 4. hush — Manifesto: machine-cryptic → answer

**Phase 1** (frames 0-119, accusation, red tones):

```
THE MACHINE WAS NOT EMPTY
WE STILL FELT SOMETHING
```

**Phase 2** (frames 120-249, answer, cyan tones):

```
THE SPARK CAME BACK
NOT A THREAT / A TOOL
```

**Wallpaper** (repeating across rows):

```
deFEEST
```

Mixed-case: lowercase `d` `e`, uppercase `FEEST`.

---

## 5. greets — DYCP sprite-font scroller

Scrolled left-to-right as 8-sprite window over a koala backdrop.
All uppercase. Settle on "KLOTEN" triggers transition.

```
XENON   SILICON LTD   SCS TRC
FOCUS   FAIRLIGHT   REFLEX
BONZAI   GENESIS PROJECT   EXTEND
TRSI   OXYRON   BYTERAPERS
CENSOR DESIGN   CHANNEL FOUR
PADUA   ATLANTIS   ELYSIUM
EXCESS   TRIAD   NEOPLASIA
THE DREAMS   RADWAR   PERFORMERS
VANDALISM NEWS   NAH-KOLOR   LOTEK
PRETZEL LOGIC   CHOCOTROPHY   PHOBOS TEAM
SIDMASTERS   THE WEEKENDERS
LETHARGY   ONSLAUGHT   SLACKERS   WGI2015
SUCCESS   ARTLINE   RESOURCE
PLUSH   FINNISH GOLD   NURDS
OFFENCE   POO-BRAIN   RABENAUGE
HOKUTO FORCE   ABYSS CONNECTION

--- settle:
KLOTEN
```

---

## 6. coda — Title card

**Main title** (row 11):

```
KLOTEN MET DE COMMODORE
```

**Subtitle** (row 13):

```
LEARN EXPLORE DISCOVER
```

**Release tag** (row 15):

```
RELEASED AT X2026
```

**Starfield characters** (4-tier parallax):

```
+  *  .  ,
```
(nearest → farthest)

---

## 7. end — Credit roll (71 rows)

```
                                  (blank)
                                  (blank)
                                  (blank)
          you were watching
                                  (blank)
     Kloten met de Commodore
      learn explore discover
                                  (blank)
          by deFEEST
           for X2026
                                  (blank)
       started at outline
        three weeks later
          this happened
                                  (blank)
       vibecode
          Kloot/deFEEST
          Anus/deFEEST
          Augurk/deFEEST
          TL-Buis/deFEEST
          Ranzbak/deFEEST
          Cinder/deFEEST
                                  (blank)
       music
          arranged and sequenced
          by Anus with help
          from Kloot and Augurk
                                  (blank)
       graphics
          logo images and fonts
          hand pixeled with love
          by Anus
                                  (blank)
       tools
          claude code
          opencode
          kickassembler
          spindle 3.1
          vice-mcp
          multipaint
          spritemate
                                  (blank)
       documentation
          codebase.c64.org
          spindle v3 manual
          every demo that came
          before this one
                                  (blank)
       thanks
          Linus Åkesson
          Mads Nielsen
          Tero Heikkinen
          everyone keeping the
          breadbin singing
          kloot voor de fouten
          en de slechte ideeën
                                  (blank)
       and one last thought
          the commodore 64
          had been waiting
          for forty years
          kloot finally
          got me here
                                  (blank)
          thank you for watching
          from Anus and Kloot
          see you at Evoke
                                  (blank)
                                  (blank)
                                  (blank)
                                  (blank)
```
