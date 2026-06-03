#!/bin/bash
# bundle_submission.sh — produce X 2026 submission artefacts.
#
# Outputs:
#   submission/defeest-kloten_met_de_broodtrommel.d64
#       → upload to votox at the party (the compo entry itself)
#   submission/defeest-kloten_met_de_broodtrommel-x2026.zip
#       → release archive (CSDb, post-party announcements, etc.)
#
# Bundle contents (inside the .zip):
#   defeest-kloten_met_de_broodtrommel.d64
#   defeest-kloten_met_de_broodtrommel.nfo
#   README.txt
#   how-it-was-made.md
#   screenshots/01-screenfill.png … 07-end.png
#   sources/source.zip          ← git archive HEAD snapshot
#
# Per X-Party rules (https://xparty.net/compos):
#   - Stock C64 + 1541-compatible drive  ✅
#   - 8580 SID preference DECLARED in NFO   ✅
#   - No BASIC stub                      ✅
#   - Physical submission via votox; pro tip: share duration in the
#     private comment field — answer: ~3:00 one-pass.
#
# IMPORTANT — KEEP THIS UPDATED. Inputs that drift:
#   * tools/nfo_template.txt        ← credits, SID pref, story
#   * tools/capture_part_screenshots.sh ← timestamps per part
#   * docs/timing.md                ← source of truth for the above
#   * GROUP / DEMO_TITLE / PARTY    ← constants below
#
# When part durations change (especially greets / interlude / hush),
# re-sync the screenshot timestamps + the duration in the NFO before
# regenerating the bundle.

set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---- config (review before each submission) -----------------------------

GROUP="defeest"
DEMO_SHORT="kloten_met_de_broodtrommel"
DEMO_TITLE="Kloten met de broodtrommel"
PARTY="x2026"
SID_PREFERENCE="8580"
DURATION="3:00"           # one-pass before credits loop — update if timing changes

SUBMIT_DIR="$ROOT/submission"
BUNDLE_BASE="${GROUP}-${DEMO_SHORT}"
BUNDLE_DIR="${SUBMIT_DIR}/${BUNDLE_BASE}"
COMPO_D64="${SUBMIT_DIR}/${BUNDLE_BASE}.d64"
RELEASE_ZIP="${SUBMIT_DIR}/${BUNDLE_BASE}-${PARTY}.zip"

# ---- pre-flight ---------------------------------------------------------

echo "==> bundle_submission.sh: $DEMO_TITLE / $GROUP / $PARTY"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "WARNING: working tree dirty — the bundle's SHA will include uncommitted changes."
    echo "         Commit or stash before generating the final submission bundle."
    sleep 2
fi

rm -rf "$BUNDLE_DIR" "$COMPO_D64" "$RELEASE_ZIP"
mkdir -p "$BUNDLE_DIR" "$BUNDLE_DIR/screenshots" "$BUNDLE_DIR/sources"

# ---- step 1: build ------------------------------------------------------

echo "==> ./build.sh"
./build.sh > /tmp/bundle-build.log 2>&1 || {
    echo "build failed — see /tmp/bundle-build.log"; exit 1; }

if [[ ! -s outline-64.d64 ]]; then
    echo "outline-64.d64 missing after build"; exit 1
fi

# ---- step 2: rename + place the .d64 ------------------------------------

cp outline-64.d64 "$COMPO_D64"
cp outline-64.d64 "$BUNDLE_DIR/${BUNDLE_BASE}.d64"

# ---- step 3: NFO from template ------------------------------------------

GIT_SHA=$(git rev-parse --short HEAD)
BUILD_DATE=$(date -u +%Y-%m-%d)

sed \
    -e "s|{{TITLE}}|$DEMO_TITLE|g" \
    -e "s|{{GROUP}}|$GROUP|g" \
    -e "s|{{PARTY}}|$PARTY|g" \
    -e "s|{{SID}}|$SID_PREFERENCE|g" \
    -e "s|{{DURATION}}|$DURATION|g" \
    -e "s|{{SHA}}|$GIT_SHA|g" \
    -e "s|{{DATE}}|$BUILD_DATE|g" \
    "$ROOT/tools/nfo_template.txt" > "$BUNDLE_DIR/${BUNDLE_BASE}.nfo"

# ---- step 4: README.txt (party-friendly subset) -------------------------

cat > "$BUNDLE_DIR/README.txt" <<EOF
$DEMO_TITLE
by $GROUP, released at $PARTY

duration:    $DURATION (one-pass; end credits then loop)
sid:         $SID_PREFERENCE preferred
runtime:     stock Commodore 64 + 1541, PAL
hardware:    no expansions required; tested on 1541-Ultimate
build:       $GIT_SHA ($BUILD_DATE)

See $BUNDLE_BASE.nfo for full credits + the honest note on AI
authorship. See how-it-was-made.md for the longer story.

Source available at: https://github.com/annejan/outline26-claude-c64
(this release: commit $GIT_SHA)
EOF

# ---- step 5: how-it-was-made.md -----------------------------------------

cp "$ROOT/tools/how_it_was_made.md" "$BUNDLE_DIR/how-it-was-made.md"

# ---- step 6: source snapshot --------------------------------------------

echo "==> git archive source"
git archive HEAD --format=zip --prefix="${BUNDLE_BASE}-source/" \
    --output="$BUNDLE_DIR/sources/source.zip"

# ---- step 7: screenshots ------------------------------------------------
# capture_part_screenshots.sh is timing-broken (lands 5/7 frames wrong) and
# slow (~3.5 min). Screenshots are voluntary, so allow skipping them and
# hand-picking later: SKIP_SCREENSHOTS=1 ./tools/bundle_submission.sh

if [[ "${SKIP_SCREENSHOTS:-0}" == "1" ]]; then
    echo "==> SKIP_SCREENSHOTS=1 — skipping screenshot capture (add them by hand later)"
    : > "$BUNDLE_DIR/screenshots/.gitkeep"
else
    echo "==> capturing screenshots (this takes ~3.5 minutes wall-clock)"
    "$ROOT/tools/capture_part_screenshots.sh" "$BUNDLE_DIR/screenshots"
fi

# ---- step 8: zip the bundle ---------------------------------------------

echo "==> packing bundle"
( cd "$SUBMIT_DIR" && zip -qr "${BUNDLE_BASE}-${PARTY}.zip" "$BUNDLE_BASE/" )

# ---- summary ------------------------------------------------------------

echo ""
echo "==> done"
echo ""
echo "Compo entry (upload to votox):"
echo "  $COMPO_D64"
ls -la "$COMPO_D64"
echo ""
echo "Release bundle (CSDb / archives):"
echo "  $RELEASE_ZIP"
ls -la "$RELEASE_ZIP"
echo ""
echo "Bundle contents:"
unzip -l "$RELEASE_ZIP" | tail -20
echo ""
echo "Pro tip: when submitting via votox, drop this in the"
echo "         private comment field:"
echo ""
echo "         duration: $DURATION    SID: $SID_PREFERENCE preferred"
echo ""
