#!/bin/bash
# where-am-i.sh — one-shot status report.
#
# Prints: current branch, uncommitted files, last few commits, open PRs,
# any local branches that haven't been deleted.
#
# Lives at tools/where-am-i.sh because the conversation pattern
# "waar waren we?" / "where were we?" keeps coming up, and the answer
# is almost always:
#   1. what branch am I on
#   2. is anything uncommitted
#   3. what just landed on main
#   4. what PRs are still open
#
# Usage: ./tools/where-am-i.sh
set -e

cd "$(dirname "$0")/.."

cyan="\033[36m"
yellow="\033[33m"
dim="\033[2m"
reset="\033[0m"

echo -e "${cyan}── branch ──────────────────────────────────────────${reset}"
git rev-parse --abbrev-ref HEAD
remote_status=$(git status -uno --porcelain=2 --branch 2>/dev/null \
    | grep -E '^# branch\.(ab|upstream)' || true)
echo -e "${dim}${remote_status}${reset}"

echo
echo -e "${cyan}── uncommitted ─────────────────────────────────────${reset}"
if [[ -z "$(git status --porcelain)" ]]; then
    echo -e "${dim}working tree clean${reset}"
else
    git status --short
fi

echo
echo -e "${cyan}── recent commits (last 5) ─────────────────────────${reset}"
git log --oneline -5

echo
echo -e "${cyan}── open PRs ────────────────────────────────────────${reset}"
if command -v gh >/dev/null 2>&1; then
    pr_out=$(gh pr list --state open 2>/dev/null || echo "")
    if [[ -z "$pr_out" ]]; then
        echo -e "${dim}no open PRs${reset}"
    else
        echo "$pr_out"
    fi
else
    echo -e "${dim}gh not installed${reset}"
fi

echo
echo -e "${cyan}── local branches other than main ──────────────────${reset}"
other=$(git branch --format='%(refname:short)' | grep -vE '^(main|\* main)$' || true)
if [[ -z "$other" ]]; then
    echo -e "${dim}only main${reset}"
else
    echo "$other"
fi

echo
echo -e "${cyan}── stashes ─────────────────────────────────────────${reset}"
stash_out=$(git stash list 2>/dev/null || true)
if [[ -z "$stash_out" ]]; then
    echo -e "${dim}no stashes${reset}"
else
    echo "$stash_out"
fi
