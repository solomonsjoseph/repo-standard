#!/usr/bin/env bash
# Usage: test-lib.sh   (run from anywhere; used as a repo-standard hook)
# Tests the portable helpers in scripts/lib.sh. Where rsync is installed, the
# copy_tree results are also compared with rsync's for the same options.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fails=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi; }

# A source tree with a hidden file, nested folders, an empty folder and an
# executable script.
src="$work/src"
mkdir -p "$src/.github/workflows" "$src/docs/dev" "$src/src/pkg" "$src/empty"
echo ci > "$src/.github/workflows/ci.yml"
echo root > "$src/README.md"
echo frag > "$src/_ci.yml"
echo code > "$src/src/pkg/main.py"
echo dev > "$src/docs/dev/index.md"
printf '#!/bin/sh\n' > "$src/run.sh"; chmod +x "$src/run.sh"

# list DIR: every path under DIR, sorted, for comparing trees.
list() { (cd "$1" && find . -mindepth 1 | LC_ALL=C sort); }

copy_tree "$src" "$work/plain"
check "copies every entry, hidden and empty folders included" "[ \"\$(list '$src')\" = \"\$(list '$work/plain')\" ]"
check "copies file contents" "cmp -s '$src/.github/workflows/ci.yml' '$work/plain/.github/workflows/ci.yml'"
check "keeps the executable bit" "[ -x '$work/plain/run.sh' ]"

copy_tree "$src/" "$work/slash/"
check "accepts trailing slashes" "[ \"\$(list '$src')\" = \"\$(list '$work/slash')\" ]"

copy_tree "$src" "$work/excl" --exclude /_ci.yml --exclude '/src/'
check "excludes a top-level file" "[ ! -e '$work/excl/_ci.yml' ]"
check "excludes a top-level folder" "[ ! -e '$work/excl/src' ]"
check "keeps the rest when excluding" "[ -f '$work/excl/docs/dev/index.md' ] && [ -f '$work/excl/README.md' ]"

mkdir -p "$work/keep"; echo mine > "$work/keep/README.md"
copy_tree "$src" "$work/keep" --ignore-existing
check "--ignore-existing keeps an existing file" "[ \"\$(cat '$work/keep/README.md')\" = mine ]"
check "--ignore-existing still adds missing files" "[ -f '$work/keep/.github/workflows/ci.yml' ]"

copy_tree "$src" "$work/over"; echo old > "$work/over/README.md"
copy_tree "$src" "$work/over"
check "overwrites an existing file by default" "[ \"\$(cat '$work/over/README.md')\" = root ]"

mkdir -p "$work/del/stale/deep" "$work/del/src"
echo x > "$work/del/stale/deep/old.md"; echo x > "$work/del/extra.md"; echo x > "$work/del/src/kept.py"
copy_tree "$src" "$work/del" --delete --exclude /src/
check "--delete removes files and folders the source lacks" "[ ! -e '$work/del/extra.md' ] && [ ! -e '$work/del/stale' ]"
check "--delete leaves excluded entries alone" "[ -f '$work/del/src/kept.py' ]"

mkdir -p "$work/types/README.md"; echo mine > "$work/types/docs"
copy_tree "$src" "$work/types" --ignore-existing 2>"$work/types.err"
check "skips a file where the destination has a folder" "[ -d '$work/types/README.md' ]"
check "skips a folder where the destination has a file" "[ \"\$(cat '$work/types/docs')\" = mine ]"
check "keeps copying after a type clash, with a note" "[ -f '$work/types/.github/workflows/ci.yml' ] && grep -q 'skipped docs/' '$work/types.err'"

check "rejects an unknown option" "! (copy_tree '$src' '$work/bad' --nope) 2>/dev/null"
check "rejects a missing source" "! (copy_tree '$work/missing' '$work/bad') 2>/dev/null"

# Symlinks: only where the platform makes real ones (Git for Windows copies
# the target instead unless developer mode is on).
ln -s README.md "$src/link.md" 2>/dev/null || true
if [ -L "$src/link.md" ]; then
  copy_tree "$src" "$work/links"
  check "copies a symlink as a symlink" "[ -L '$work/links/link.md' ]"
  mkdir -p "$work/outside" "$work/linked"; ln -s ../outside "$work/linked/docs"
  copy_tree "$src" "$work/linked" --ignore-existing 2>/dev/null
  check "never writes through a symlinked destination folder" "[ -z \"\$(ls -A '$work/outside')\" ]"
else
  echo "skip  symlink test (this platform does not create symlinks)"
fi

if command -v rsync >/dev/null; then
  # Fresh copies: the symlink test above added to the source after
  # $work/plain was made.
  rsync -a "$src/" "$work/r-plain/"
  copy_tree "$src" "$work/plain2"
  check "matches rsync -a" "[ \"\$(list '$work/plain2')\" = \"\$(list '$work/r-plain')\" ]"
  rsync -a --exclude /_ci.yml --exclude /src/ "$src/" "$work/r-excl/"
  copy_tree "$src" "$work/excl2" --exclude /_ci.yml --exclude /src/
  check "matches rsync -a --exclude" "[ \"\$(list '$work/excl2')\" = \"\$(list '$work/r-excl')\" ]"
else
  echo "skip  rsync comparison (rsync not installed)"
fi

[ "$fails" = 0 ] || { echo "$fails test(s) failed"; exit 1; }
