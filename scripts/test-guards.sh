#!/usr/bin/env bash
# Usage: test-guards.sh   (run from anywhere; used as a repo-standard hook)
# Tests the pre-push guard (scripts/git-hooks/pre-push) against a local bare
# remote (which pushes to main it refuses and which it allows), and the
# ascii-only and no-invisible-unicode hook patterns in template/.
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


# The ascii-only exclude and the no-invisible-unicode pattern, read from the
# template config the way pre-commit applies them (pygrep matches bytes).
unicode="$(python3 - "$root/template/.pre-commit-config.yaml" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
def field(hook, key):
    block = text.split("id: " + hook, 1)[1].split("- id:", 1)[0]
    return re.search(r"^\s*" + key + r": (.*)$", block, re.M).group(1).strip()
exclude = re.compile(field("ascii-only", "exclude"))
entry = field("no-invisible-unicode", "entry").strip('"').replace("\\\\", "\\")
invisible = re.compile(entry.encode())
fails = 0
def expect(name, got, want):
    global fails
    print(("ok    " if got == want else "FAIL  ") + name)
    fails += got != want
for path, skipped in [("docs/guide.md", True), ("locales/fa.json", True),
                      ("pkg/parser/testdata/input.json", True), ("tests/fixtures/synthetic/a.csv", True),
                      ("requirements.txt", False), ("src/i18n/index.ts", False),
                      ("src/locales/loader.py", False), ("notes.txt", False)]:
    expect(f"ascii-only {'skips' if skipped else 'checks'} {path}", bool(exclude.search(path)), skipped)
for code, blocked in [(0x202E, True), (0x2066, True), (0x200B, True), (0x2060, True),
                      (0x200C, False), (0x200D, False), (0x200E, False), (0x061C, False), (0xFEFF, False)]:
    data = ("a" + chr(code) + "b").encode()
    expect(f"no-invisible-unicode {'blocks' if blocked else 'allows'} U+{code:04X}", bool(invisible.search(data)), blocked)
sys.exit(1 if fails else 0)
PY
)" || fails=$((fails + 1))
echo "$unicode"
[ "$fails" = 0 ] || { echo "$fails test(s) failed"; exit 1; }
