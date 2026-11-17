#!/usr/bin/env bash
# Usage: test-guards.sh   (run from anywhere; used as a repo-standard hook)
# Tests the pre-push guard (scripts/git-hooks/pre-push) against a local bare
# remote: which pushes to main it refuses and which it allows.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fails=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi; }
g() { git -C "$work/w" -c user.name=test -c user.email=test@example.com -c core.autocrlf=false "$@"; }
push() { g push -q origin "$@" >/dev/null 2>&1; }
commit() { echo "$1" > "$work/w/$1"; g add "$1"; g commit -qm "$1"; }

git init -q --bare "$work/remote.git"
git init -q -b main "$work/w"
cp "$root/scripts/git-hooks/pre-push" "$work/w/.git/hooks/pre-push"
chmod +x "$work/w/.git/hooks/pre-push"
printf 'repos:\n  - repo: local\n    hooks:\n      - id: no-commit-to-branch\n' > "$work/w/.pre-commit-config.yaml"
g add -A; g commit -qm init
g remote add origin "$work/remote.git"

check "allows the bootstrap push that creates main" "push main"
commit a
check "refuses a push to main" "! push main"
check "refuses a push to main by refspec" "! push HEAD:refs/heads/main"
check "allows a push to a branch" "push main:feat"
check "refuses deleting main" "! push :main"
g rm -q .pre-commit-config.yaml; g commit -qm unguard
check "leaves a repository that does not follow the standard alone" "push main"

[ "$fails" = 0 ] || { echo "$fails test(s) failed"; exit 1; }
