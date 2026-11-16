#!/usr/bin/env bash
# Shared helpers for repo-standard scripts. Source this file, do not run it.
set -euo pipefail

STANDARD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export STANDARD_ROOT

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# gh_as OWNER ARGS...: run gh with the owner's own token. Never switches the
# active account (global rule: no `gh auth switch`).
gh_as() {
  local owner="$1"; shift
  local token
  token="$(gh auth token --user "$owner" 2>/dev/null)" ||
    die "no gh login for $owner; run: gh auth login (as $owner)"
  GH_TOKEN="$token" gh "$@"
}

# Substitute template placeholders in every text file under a directory.
# __OWNER_ID__ is the owner's numeric GitHub id (for noreply addresses).
render_placeholders() {
  local dir="$1" owner="$2" name="$3" pkg="$4" desc="$5"
  local f owner_id
  owner_id="$(gh_as "$owner" api user --jq .id 2>/dev/null || echo 0)"
  while IFS= read -r -d '' f; do
    if grep -Iq . "$f" 2>/dev/null; then
      OWNER="$owner" OID="$owner_id" NAME="$name" PKG="$pkg" DESC="$desc" perl -pi -e \
        's/__OWNER_ID__/$ENV{OID}/g; s/__OWNER__/$ENV{OWNER}/g; s/__REPO_NAME__/$ENV{NAME}/g; s/__PKG__/$ENV{PKG}/g; s/__DESCRIPTION__/$ENV{DESC}/g' "$f"
    fi
  done < <(find "$dir" -type f -not -path '*/.git/*' -print0)
  # Rename files and folders whose own name holds a placeholder. Deepest
  # first, and only the last path part, so parents are renamed after children.
  find "$dir" -depth \( -name '*__PKG__*' -o -name '*__REPO_NAME__*' \) -not -path '*/.git/*' |
    while read -r p; do
      local base="${p##*/}" nb
      nb="${base//__PKG__/$pkg}"; nb="${nb//__REPO_NAME__/$name}"
      mv "$p" "${p%/*}/$nb"
    done
}

# Private per-owner settings live outside the repo so the public standard never
# names the owner's accounts: ~/.config/repo-standard/OWNER.env with
#   OWNER_NAME="Display Name"          commit and LICENSE name (required)
#   RELEASE_APP_CLIENT_ID=Iv1...       release App client id (public id)
#   SIGNING_KEY=~/.ssh/id_ed25519.pub  SSH key for commit signing (optional)
CONFIG_DIR="${REPO_STANDARD_CONFIG:-$HOME/.config/repo-standard}"

# load_owner OWNER: refuse owners without a private config (the scripts run
# outside the identity hook's guard, so this is their unknown-owner check),
# then load the owner's settings.
load_owner() {
  local conf="$CONFIG_DIR/$1.env"
  [ -f "$conf" ] || die "unknown owner '$1': create $conf (see scripts/lib.sh)"
  # RELEASE_APP_CLIENT_ID is read by the scripts that call load_owner.
  OWNER_NAME=""; export RELEASE_APP_CLIENT_ID=""; SIGNING_KEY=""
  # shellcheck disable=SC1090
  source "$conf"
  [ -n "$OWNER_NAME" ] || die "$conf has no OWNER_NAME"
}

# owner_name OWNER: display name used for commits and LICENSE holders.
owner_name() { load_owner "$1"; echo "$OWNER_NAME"; }

# set_identity DIR OWNER: local commit identity, credential helper and (when
# SIGNING_KEY is set) SSH commit signing for the owner. Never global. The
# helper string matches ~/.claude/hooks/git-identity-switch.sh so the hook
# leaves it alone.
set_identity() {
  local dir="$1" owner="$2" id gh_bin
  load_owner "$owner"
  id="$(gh_as "$owner" api user --jq .id)"
  gh_bin="$(command -v gh)"
  git -C "$dir" config --local user.name "$OWNER_NAME"
  git -C "$dir" config --local user.email "${id}+${owner}@users.noreply.github.com"
  git -C "$dir" config --local --unset-all credential.https://github.com.helper 2>/dev/null || true
  git -C "$dir" config --local credential.https://github.com.helper ""
  git -C "$dir" config --local --add credential.https://github.com.helper \
    "!f() { test \"\$1\" = get || exit 0; echo username=${owner}; echo \"password=\$('${gh_bin}' auth token --user ${owner})\"; }; f"
  if [ -n "$SIGNING_KEY" ]; then
    git -C "$dir" config --local gpg.format ssh
    git -C "$dir" config --local user.signingkey "${SIGNING_KEY/#\~/$HOME}"
    git -C "$dir" config --local commit.gpgsign true
  else
    echo "warning: no SIGNING_KEY in $CONFIG_DIR/$owner.env; commits are unsigned" >&2
  fi
}

# write_license DIR OWNER SPDX|none: add the chosen license, or note "no
# license" in the README so its LICENSE link is not left dangling.
write_license() {
  local dir="$1" owner="$2" license="$3" year holder
  if [ "$license" = none ]; then
    rm -f "$dir/LICENSE"
    perl -0pi -e 's/See \[LICENSE\]\(LICENSE\)\./No license: all rights reserved./' "$dir/README.md"
    return
  fi
  info "adding license $license"
  year="$(date +%Y)"; holder="$(owner_name "$owner")"
  # Apache-2.0 keeps its appendix placeholders: they are the header template.
  gh_as "$owner" api "licenses/$license" --jq .body |
    if [ "$license" = apache-2.0 ]; then cat; else
      Y="$year" H="$holder" perl -pe 's/\[year\]|\[yyyy\]/$ENV{Y}/g; s/\[fullname\]|\[name of copyright owner\]/$ENV{H}/g'
    fi | perl -0pe 's/\s+\z/\n/' > "$dir/LICENSE"  # exactly one final newline (end-of-file hook)
}

# make_locks DIR OVERLAY: generate the lock files CI installs from.
make_locks() {
  case "$2" in
    python) if command -v uv >/dev/null; then (cd "$1" && uv lock); else echo "warning: uv not found; run 'uv lock' before the first PR"; fi ;;
    ts) if command -v pnpm >/dev/null; then (cd "$1" && pnpm install); else echo "warning: pnpm not found; run 'pnpm install' before the first PR"; fi ;;
  esac
}

# copy_tree SRC DST [--ignore-existing] [--delete] [--exclude /NAME]...
# Portable stand-in for `rsync -a SRC/ DST/`, because Git for Windows ships no
# rsync. Copies the contents of SRC (hidden files included) into DST, keeping
# modes, times and symlinks. --exclude names a top-level entry of SRC, like an
# anchored rsync pattern (`/src/` or `/_ci.yml`). --ignore-existing keeps files
# DST already has. --delete removes what SRC does not have (excluded entries
# are left alone, as rsync does).
copy_tree() {
  local src="${1%/}" dst="${2%/}" keep=0 del=0 rel top e skip
  local -a excl=()
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --ignore-existing) keep=1 ;;
      --delete) del=1 ;;
      --exclude) top="${2#/}"; excl+=("${top%/}"); shift ;;
      *) die "copy_tree: unknown option $1" ;;
    esac
    shift
  done
  [ -d "$src" ] || die "copy_tree: $src is not a directory"
  mkdir -p "$dst"
  # find lists a folder before its contents, so folders exist before files.
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"; top="${rel%%/*}"; skip=0
    for e in ${excl[@]+"${excl[@]}"}; do [ "$top" = "$e" ] && skip=1; done
    [ "$skip" = 1 ] && continue
    if [ -d "$src/$rel" ] && [ ! -L "$src/$rel" ]; then
      mkdir -p "$dst/$rel"
      continue
    fi
    if [ "$keep" = 1 ] && { [ -e "$dst/$rel" ] || [ -L "$dst/$rel" ]; }; then continue; fi
    rm -f "$dst/$rel"  # replace a symlink instead of writing through it
    cp -Pp "$src/$rel" "$dst/$rel"
  done < <(cd "$src" && find . -mindepth 1 -print0)
  [ "$del" = 1 ] || return 0
  # Deepest first, so a folder is checked after everything inside it.
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"; top="${rel%%/*}"; skip=0
    for e in ${excl[@]+"${excl[@]}"}; do [ "$top" = "$e" ] && skip=1; done
    [ "$skip" = 1 ] && continue
    { [ -e "$src/$rel" ] || [ -L "$src/$rel" ]; } || rm -rf "${dst:?}/$rel"
  done < <(cd "$dst" && find . -mindepth 1 -depth -print0)
}

# File-name rule shared with the no-scratch-files pre-commit hook (keep the two
# in sync; scripts/check-drift.sh verifies it in repo-standard).
# shellcheck disable=SC2034  # used by audit.sh
SCRATCH_NAME_RE='(^|/)([^/]*[-_.])?(plans?|notes|research|sessions?|drafts?|scratch|todos?|brainstorm(ing)?|handoffs?|worklogs?)([-_.][^/]*)?\.(md|mdx|txt)$'
# shellcheck disable=SC2034
SCRATCH_EXEMPT_RE='^(docs/(?!dev/).*|docs/dev/adr/.*|(.*/)?release[-_]notes[^/]*)$'

# is_source_owner OWNER: true for the account that hosts the public source
# repo-standard (REPO_STANDARD_SOURCE_OWNER in the private source.env).
is_source_owner() {
  local REPO_STANDARD_SOURCE_OWNER=""
  # shellcheck disable=SC1091
  [ -f "$CONFIG_DIR/source.env" ] && source "$CONFIG_DIR/source.env"
  [ -n "$REPO_STANDARD_SOURCE_OWNER" ] || die "set REPO_STANDARD_SOURCE_OWNER in $CONFIG_DIR/source.env"
  [ "$1" = "$REPO_STANDARD_SOURCE_OWNER" ]
}

# delink_standard DIR: for accounts that must stay unlinked from the source
# account, replace links to a repo-standard copy with plain text, because
# their copies of the standard are private.
delink_standard() {
  local f
  for f in "$1/CONTRIBUTING.md" "$1/AGENTS.md"; do
    [ -f "$f" ] || continue
    perl -0pi -e 's/the\s*\n?\[repo standard\]\(https:\/\/github\.com\/[^)\s]+\/repo-standard\/blob\/main\/STANDARD\.md\)/its owner\x27s repository standard/g' "$f"
  done
}

# Per-repo exclude list: DIR/.github/repo-standard-exclude names standard
# files, folders (ending in /), hooks (hook:<id>) and .gitignore patterns
# (gitignore:<pattern>) the repo has chosen not to use. One entry per line;
# text after # is a comment (the reason).
EXCLUDE_FILE=.github/repo-standard-exclude
# excluded DIR ENTRY: true when ENTRY (a path or hook:<id>) is on DIR's list.
# A folder entry also covers every path inside it.
excluded() {
  local list="$1/$EXCLUDE_FILE" entry
  [ -f "$list" ] || return 1
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry%%#*}"; entry="$(echo "$entry" | tr -d '[:space:]')"
    [ -n "$entry" ] || continue
    [ "$2" = "$entry" ] && return 0
    case "$entry" in */) case "$2" in "$entry"*|"${entry%/}") return 0 ;; esac ;; esac
  done < "$list"
  return 1
}
