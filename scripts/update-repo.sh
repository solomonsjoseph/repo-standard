#!/usr/bin/env bash
# Usage: update-repo.sh DIR [--to REF] [--from REF] [--owner O] [--name N]
#          [--desc TEXT] [--no-branch] [--dry-run]
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
#               repo-standard clone (default: the newest v* tag). It must be
#               newer than --from.
#   --from REF  version the repository follows (default: v + standard-version
#               from .github/repo-standard.yml).
#   --owner/--name  placeholders (default: from the origin remote).
#   --desc TEXT     the description placeholder, for files the update adds
#                   (default: the GitHub description, else the name).
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
to=""; from=""; owner=""; name=""; desc=""; branch=1; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --to) to="${2:?--to needs a ref}"; shift ;;
    --from) from="${2:?--from needs a ref}"; shift ;;
    --owner) owner="${2:?}"; shift ;;
    --name) name="${2:?}"; shift ;;
    --desc) desc="${2:?}"; shift ;;
    --no-branch) branch=0 ;;
    --dry-run) dry=1 ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
[ -d "$dir" ] || die "$dir does not exist"
dir="$(cd "$dir" && pwd)"
stamp="$dir/$STAMP_FILE"
[ -f "$stamp" ] || die "$stamp is missing: run apply-overlay.sh --retrofit first, or write it by hand (see STANDARD.md)"
overlay="$(stamp_field "$stamp" overlay)"
addons="$(stamp_field "$stamp" addons | tr -d '[]' | tr ',' ' ')"
visibility="$(stamp_field "$stamp" visibility)"
[ -n "$overlay" ] && [ "$overlay" != none ] || die "$stamp names no language overlay"
# A worktree or submodule has a .git file, not a folder, so ask git.
is_repo=0; git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_repo=1

if [ -z "$owner" ] || [ -z "$name" ]; then
  slug="$(origin_slug "$dir")"
  owner="${owner:-${slug%%/*}}"; name="${name:-${slug#*/}}"
fi
[ -n "$owner" ] && [ -n "$name" ] || die "no GitHub origin remote: pass --owner and --name"
if [ -z "$desc" ]; then
  # Subshell: gh_as exits through die when the owner has no gh login.
  desc="$( (gh_as "$owner" repo view "$owner/$name" --json description --jq .description) 2>/dev/null || true)"
  desc="${desc:-$name}"
fi

# resolve REF: the commit of a git ref of this clone; a bare version 1.4.0
# means tag v1.4.0. Later git commands get the commit, never REF:path, which
# Git Bash would rewrite as a Windows path when REF has a slash.
resolve() {
  local ref="$1"
  case "$ref" in [0-9]*) ref="v$ref" ;; esac
  git -C "$STANDARD_ROOT" rev-parse --verify --quiet "$ref^{commit}" ||
    die "unknown ref $ref in $STANDARD_ROOT: run 'git fetch --tags', or pass --from/--to with a commit (a version without a release has no tag)"
}
if [ -z "$to" ]; then
  to="$(git -C "$STANDARD_ROOT" tag --list 'v*' --sort=-v:refname | head -n 1)"
  [ -n "$to" ] || die "no v* tags in $STANDARD_ROOT; pass --to REF (git fetch --tags?)"
fi
if [ -z "$from" ]; then
  from="$(stamp_field "$stamp" standard-version)"
  [ -n "$from" ] || die "$stamp has no standard-version; pass --from REF"
fi
case "$from" in [0-9]*) from="v$from" ;; esac
case "$to" in [0-9]*) to="v$to" ;; esac
from_sha="$(resolve "$from")"; to_sha="$(resolve "$to")"
[ "$from_sha" != "$to_sha" ] || { info "already on $to; nothing to do"; exit 0; }
git -C "$STANDARD_ROOT" merge-base --is-ancestor "$from_sha" "$to_sha" ||
  die "$to is not newer than $from; an update never goes back (pass --from if the stamp is wrong)"
to_version="$(git -C "$STANDARD_ROOT" show "$to_sha:.release-please-manifest.json" 2>/dev/null |
  sed -nE 's/.*"\."[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
[ -n "$to_version" ] || die "$to has no .release-please-manifest.json version"

if [ "$dry" = 0 ] && [ "$is_repo" = 1 ] && [ -n "$(git -C "$dir" status --porcelain)" ]; then
  die "$dir has uncommitted changes; commit or stash them first"
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# render COMMIT OUT: the files a new repository got from the standard at
# COMMIT, built with that commit's own template, overlays and scripts.
render() {
  local ref="$1" out="$2" src="$work/src-${2##*/}" a
  mkdir -p "$src" "$out"
  git -C "$STANDARD_ROOT" archive "$ref" | tar -x -C "$src"
  [ -x "$src/scripts/apply-overlay.sh" ] || die "$ref has no scripts/apply-overlay.sh"
  copy_tree "$src/template" "$out"
  local pub=(); [ "$visibility" = public ] && pub=(--public)
  "$src/scripts/apply-overlay.sh" "$out" "$overlay" ${pub[@]+"${pub[@]}"} \
    --owner "$owner" --name "$name" --desc "$desc" >/dev/null
  for a in $addons; do
    "$src/scripts/apply-overlay.sh" "$out" "$a" --owner "$owner" --name "$name" --desc "$desc" >/dev/null
  done
}
info "rendering the standard at $from and $to ($overlay${addons:+ +$addons}, ${visibility:-private})"
render "$from_sha" "$work/base"
render "$to_sha" "$work/new"

park="$dir/.scratch/repo-standard-update"
excl="$(exclude_entries "$dir/$EXCLUDE_FILE")"
added=0; updated=0; removed=0; conflicts=0; notes=0
say() { printf '%-9s %s\n' "$1" "$2"; }
park_copy() {
  conflicts=$((conflicts + 1)); say CONFLICT "$1: $2"
  [ "$dry" = 1 ] && return 0
  mkdir -p "$park/$(dirname "$1")"; cp "$work/new/$1" "$park/$1"
  say "" "  the standard's version is in .scratch/repo-standard-update/$1"
}
# is_binary FILE: a non-empty file that grep sees as binary. An empty file
# is text, so it still gets a line merge.
is_binary() { [ -s "$1" ] && ! grep -Iq '' "$1"; }

if [ "$dry" = 0 ] && [ "$branch" = 1 ] && [ "$is_repo" = 1 ]; then
  git -C "$dir" switch -q -c "chore/update-repo-standard-$to_version" ||
    die "could not create branch chore/update-repo-standard-$to_version"
  info "on branch chore/update-repo-standard-$to_version"
fi

# Sample source and tests belong to the repository once it exists, and the
# stamp is updated below.
skip_re='^(src|tests|Sources|Tests|cmd|internal|R|api)/|^\.github/repo-standard\.yml$'
paths="$( { (cd "$work/base" && find . -type f); (cd "$work/new" && find . -type f); } |
  sed 's#^\./##' | grep -vE "$skip_re" | sort -u)"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  b="$work/base/$rel"; n="$work/new/$rel"; o="$dir/$rel"
  if [ -f "$b" ] && [ -f "$n" ] && cmp -s "$b" "$n"; then continue; fi
  if in_excludes "$rel" "$excl"; then say SKIPPED "$rel (on the repo's exclude list)"; notes=$((notes + 1)); continue; fi
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
  elif [ "$rel" = .gitignore ]; then
    # Ignore lists are sets, and retrofits put the standard's lines under
    # their own header, so a line merge would conflict for no reason. Add
    # the patterns the new version gained; never remove the repo's.
    grep -vxF -f "$b" "$n" | grep -vE '^[[:space:]]*(#|$)' | grep -vxF -f "$o" > "$work/gained" || true
    new_lines="$(while IFS= read -r line; do
      in_excludes "gitignore:$line" "$excl" || printf '%s\n' "$line"; done < "$work/gained")"
    [ -n "$new_lines" ] || continue
    say UPDATED "$rel (added: $(printf '%s' "$new_lines" | tr '\n' ' '))"; updated=$((updated + 1))
    [ "$dry" = 1 ] || merge_gitignore "$work/gained" "$o" "$dir"
  elif is_binary "$o" || is_binary "$n"; then
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

[ "$dry" = 1 ] || set_stamp_field "$stamp" standard-version "$to_version"
echo
echo "result: $added added, $updated updated, $removed removed, $conflicts conflicts, $notes notes ($from -> $to)"
if [ "$dry" = 1 ]; then echo "dry run: nothing was written"
else
  echo "next: review 'git diff', run 'pre-commit run --all-files', then commit as"
  echo "  chore: update to repo-standard $to_version"
fi
[ "$conflicts" -eq 0 ]
