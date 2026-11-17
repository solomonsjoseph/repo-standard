#!/usr/bin/env bash
# Usage: update-repo.sh DIR [--to REF] [--from REF] [--owner O] [--name N]
#          [--no-branch] [--dry-run]
#
# Brings a repository that follows the standard up to a newer release of it,
# keeping the repository's own changes. For every file the standard manages,
# it renders the template and overlays at two versions of the standard (the
# one the repository follows, and the target), each with that version's own
# scripts, and merges the difference into the repository's copy with
# `git merge-file`: a three-way merge where the repository's copy is "ours",
# the old render is the base and the new render is "theirs".
#
#   --to REF    target version: a tag such as v1.4.0, or any git ref of this
#               repo-standard clone (default: the newest v* tag).
#   --from REF  version the repository follows (default: v + standard-version
#               from .github/repo-standard.yml).
#   --owner/--name  placeholders (default: from the origin remote).
#   --no-branch     change files on the current branch.
#   --dry-run       report what would change; write nothing.
#
# Files on the repository's exclude list (.github/repo-standard-exclude) are
# never touched; sample source and tests are never updated. Changes are left
# uncommitted on branch chore/update-repo-standard-VERSION for review. Exit
# status: 0 clean, 1 conflicts to resolve (conflict markers in the file, or
# the standard's copy in .scratch/repo-standard-update/).
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

dir="${1:?repository folder}"; shift
to=""; from=""; owner=""; name=""; branch=1; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --to) to="${2:?--to needs a ref}"; shift ;;
    --from) from="${2:?--from needs a ref}"; shift ;;
    --owner) owner="${2:?}"; shift ;;
    --name) name="${2:?}"; shift ;;
    --no-branch) branch=0 ;;
    --dry-run) dry=1 ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
[ -d "$dir" ] || die "$dir does not exist"
dir="$(cd "$dir" && pwd)"
stamp="$dir/.github/repo-standard.yml"
[ -f "$stamp" ] || die "$stamp is missing: run apply-overlay.sh --retrofit first, or write it by hand (see STANDARD.md)"
stamp_field() { sed -nE "s/^$1: *([^#]*[^ #]).*/\\1/p" "$stamp" | head -n 1; }
overlay="$(stamp_field overlay)"; addons="$(stamp_field addons | tr -d '[]' | tr ',' ' ')"
visibility="$(stamp_field visibility)"
[ -n "$overlay" ] && [ "$overlay" != none ] || die "$stamp names no language overlay"

if [ -z "$owner" ] || [ -z "$name" ]; then
  slug="$(git -C "$dir" remote get-url origin 2>/dev/null |
    sed -nE 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//' || true)"
  owner="${owner:-${slug%%/*}}"; name="${name:-${slug#*/}}"
fi
[ -n "$owner" ] && [ -n "$name" ] || die "no GitHub origin remote: pass --owner and --name"

# resolve REF: a git ref of this clone; a bare version 1.4.0 means tag v1.4.0.
resolve() {
  local ref="$1"
  case "$ref" in [0-9]*) ref="v$ref" ;; esac
  git -C "$STANDARD_ROOT" rev-parse --verify --quiet "$ref^{commit}" >/dev/null ||
    die "unknown ref $ref in $STANDARD_ROOT (git fetch --tags?)"
  echo "$ref"
}
if [ -z "$to" ]; then
  to="$(git -C "$STANDARD_ROOT" tag --list 'v*' --sort=-v:refname | head -n 1)"
  [ -n "$to" ] || die "no v* tags in $STANDARD_ROOT; pass --to REF (git fetch --tags?)"
fi
to="$(resolve "$to")"
if [ -z "$from" ]; then
  from="$(stamp_field standard-version)"
  [ -n "$from" ] || die "$stamp has no standard-version; pass --from REF"
fi
from="$(resolve "$from")"
[ "$(git -C "$STANDARD_ROOT" rev-parse "$from^{commit}")" != "$(git -C "$STANDARD_ROOT" rev-parse "$to^{commit}")" ] ||
  { info "already on $to; nothing to do"; exit 0; }
to_version="$(git -C "$STANDARD_ROOT" show "$to:.release-please-manifest.json" |
  sed -nE 's/^[[:space:]]*"\.": "([^"]+)".*/\1/p')"
[ -n "$to_version" ] || die "$to has no .release-please-manifest.json version"

if [ "$dry" = 0 ] && [ -d "$dir/.git" ] && [ -n "$(git -C "$dir" status --porcelain)" ]; then
  die "$dir has uncommitted changes; commit or stash them first"
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# render REF OUT: the files a new repository got from the standard at REF,
# built with REF's own template, overlays and scripts.
render() {
  local ref="$1" out="$2" src="$work/src-${2##*/}" a
  mkdir -p "$src" "$out"
  git -C "$STANDARD_ROOT" archive "$ref" | tar -x -C "$src"
  [ -x "$src/scripts/apply-overlay.sh" ] || die "$ref has no scripts/apply-overlay.sh"
  copy_tree "$src/template" "$out"
  local pub=(); [ "$visibility" = public ] && pub=(--public)
  "$src/scripts/apply-overlay.sh" "$out" "$overlay" ${pub[@]+"${pub[@]}"} \
    --owner "$owner" --name "$name" >/dev/null
  for a in $addons; do
    "$src/scripts/apply-overlay.sh" "$out" "$a" --owner "$owner" --name "$name" >/dev/null
  done
}
info "rendering the standard at $from and $to ($overlay${addons:+ +$addons}, ${visibility:-private})"
render "$from" "$work/base"
render "$to" "$work/new"

park="$dir/.scratch/repo-standard-update"
added=0; updated=0; removed=0; conflicts=0; notes=0
say() { printf '%-9s %s\n' "$1" "$2"; }
park_copy() {
  conflicts=$((conflicts + 1)); say CONFLICT "$1: $2"
  [ "$dry" = 1 ] && return 0
  mkdir -p "$park/$(dirname "$1")"; cp "$work/new/$1" "$park/$1"
  say "" "  the standard's version is in .scratch/repo-standard-update/$1"
}

if [ "$dry" = 0 ] && [ "$branch" = 1 ] && [ -d "$dir/.git" ]; then
  git -C "$dir" switch -q -c "chore/update-repo-standard-$to_version" ||
    die "could not create branch chore/update-repo-standard-$to_version"
  info "on branch chore/update-repo-standard-$to_version"
fi

# Sample source and tests belong to the repository once it exists, and the
# stamp is rewritten below.
skip_re='^(src|tests|Sources|Tests|cmd|internal|R|api)/|^\.github/repo-standard\.yml$'
paths="$( { (cd "$work/base" && find . -type f); (cd "$work/new" && find . -type f); } |
  sed 's#^\./##' | grep -vE "$skip_re" | sort -u)"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  b="$work/base/$rel"; n="$work/new/$rel"; o="$dir/$rel"
  if [ -f "$b" ] && [ -f "$n" ] && cmp -s "$b" "$n"; then continue; fi
  if excluded "$dir" "$rel"; then say SKIPPED "$rel (on the repo's exclude list)"; notes=$((notes + 1)); continue; fi
  if [ ! -f "$b" ]; then
    # New in the standard.
    if [ ! -f "$o" ]; then
      say ADDED "$rel"; added=$((added + 1))
      [ "$dry" = 1 ] || { mkdir -p "$(dirname "$o")"; cp -p "$n" "$o"; }
    elif ! cmp -s "$o" "$n"; then
      park_copy "$rel" "new in the standard, but the repo already has its own"
    fi
  elif [ ! -f "$n" ]; then
    # Dropped by the standard: remove it only if the repo never changed it.
    [ -f "$o" ] || continue
    if cmp -s "$o" "$b"; then
      say REMOVED "$rel"; removed=$((removed + 1))
      [ "$dry" = 1 ] || rm -f "$o"
    else
      say KEPT "$rel (dropped by the standard, changed in the repo: remove it by hand if unused)"; notes=$((notes + 1))
    fi
  elif [ ! -f "$o" ]; then
    say MISSING "$rel (changed in the standard; the repo has no copy: restore it, or add it to the exclude list)"
    notes=$((notes + 1))
  elif ! grep -Iq . "$o" || ! grep -Iq . "$n"; then
    if cmp -s "$o" "$b"; then
      say UPDATED "$rel"; updated=$((updated + 1)); [ "$dry" = 1 ] || cp "$n" "$o"
    else
      park_copy "$rel" "binary file changed in both"
    fi
  else
    merged="$work/merged"; cp "$o" "$merged"
    rc=0; git merge-file -q -L repository -L "$from" -L "$to" "$merged" "$b" "$n" || rc=$?
    if [ "$rc" -lt 0 ] || [ "$rc" -gt 127 ]; then die "git merge-file failed on $rel"; fi
    cmp -s "$merged" "$o" && continue
    if [ "$rc" -eq 0 ]; then
      say UPDATED "$rel"; updated=$((updated + 1))
    else
      conflicts=$((conflicts + 1)); say CONFLICT "$rel: $rc conflicting section(s); resolve the <<<<<<< markers"
    fi
    [ "$dry" = 1 ] || cat "$merged" > "$o"
  fi
  # Keep the standard's executable bit on files the update touched.
  if [ "$dry" = 0 ] && [ -f "$o" ] && [ -x "$n" ] && [ ! -x "$o" ]; then chmod +x "$o"; fi
done <<< "$paths"

if [ "$dry" = 0 ]; then
  perl -pi -e "s/^standard-version:[ ]*[^ #\\n]+/standard-version: $to_version/" "$stamp"
fi
echo
echo "result: $added added, $updated updated, $removed removed, $conflicts conflicts, $notes notes ($from -> $to)"
if [ "$dry" = 1 ]; then echo "dry run: nothing was written"
else
  echo "next: review 'git diff', run 'pre-commit run --all-files', then commit as"
  echo "  chore: update to repo-standard $to_version"
fi
[ "$conflicts" -eq 0 ]
