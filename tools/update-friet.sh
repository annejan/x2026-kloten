#!/bin/bash
# Update friet.prg from the friet-met-desire repository.
#
# Usage:  ./tools/update-friet.sh
#
# Builds the standalone player from the friet-met-desire repo and copies
# the resulting .prg to parts/friet-met-desire/friet.prg so build.sh can
# bundle it.
#
# The friet source repo is cloned to /tmp on first run (or use a sibling
# directory ../friet-met-desire if already checked out).
set -eo pipefail

ROOT="$(dirname "$(readlink -f "$0")")/.."
FRIET_REPO="https://github.com/annejan/friet-met-desire.git"

# Look for existing checkout
if [[ -d "$ROOT/../friet-met-desire" ]]; then
    FRIET_DIR="$(realpath "$ROOT/../friet-met-desire")"
    echo "Using sibling checkout: $FRIET_DIR"
elif [[ -d /tmp/friet-met-desire ]]; then
    FRIET_DIR=/tmp/friet-met-desire
    echo "Updating /tmp/friet-met-desire"  
    git -C "$FRIET_DIR" pull --ff-only
else
    echo "Cloning friet-met-desire to /tmp/friet-met-desire"
    git clone "$FRIET_REPO" /tmp/friet-met-desire
    FRIET_DIR=/tmp/friet-met-desire
fi

# Build the player — needs Python deps (mido, pyyaml, numpy) + KickAssembler
echo "Building player in $FRIET_DIR..."
(cd "$FRIET_DIR" && make player 2>&1)

# Copy result
cp "$FRIET_DIR/out/friet.prg" "$ROOT/parts/friet-met-desire/friet.prg"
echo "Copied friet.prg ($(wc -c < "$ROOT/parts/friet-met-desire/friet.prg") bytes)"
