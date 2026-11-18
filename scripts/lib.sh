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
#   SECURITY_CONTACT="..."             private repos' SECURITY.md contact, such
#                                      as an address or a form URL (optional)
CONFIG_DIR="${REPO_STANDARD_CONFIG:-$HOME/.config/repo-standard}"

# load_owner OWNER: refuse owners without a private config (the scripts run
# outside the identity hook's guard, so this is their unknown-owner check),
# then load the owner's settings.
load_owner() {
  local conf="$CONFIG_DIR/$1.env"
  [ -f "$conf" ] || die "unknown owner '$1': create $conf (see scripts/lib.sh)"
  # RELEASE_APP_CLIENT_ID is read by the scripts that call load_owner.
  OWNER_NAME=""; export RELEASE_APP_CLIENT_ID=""; SIGNING_KEY=""
  # shellcheck disable=SC2034  # read by apply-overlay.sh
  SECURITY_CONTACT=""
  # shellcheck disable=SC1090
  source "$conf"
  [ -n "$OWNER_NAME" ] || die "$conf has no OWNER_NAME"
}

# owner_name OWNER: display name used for commits and LICENSE holders.
owner_name() { load_owner "$1"; echo "$OWNER_NAME"; }
# act_as_account: the account in CONFIG_DIR/act-as (one account acts in every
# repository), or nothing when the file does not exist.
act_as_account() { [ -f "$CONFIG_DIR/act-as" ] && tr -d '[:space:]' < "$CONFIG_DIR/act-as" || true; }

# set_identity DIR OWNER: local commit identity, credential helper and (when
# SIGNING_KEY is set) SSH commit signing for the owner. Never global. The
# identity hook (scripts/claude-hooks/git-identity-switch.sh) calls this too,
# and recognises a clone as already set by the "username=OWNER;" in the helper.
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
    perl -0pi -e 's/See \[LICENSE\]\(LICENSE\)\./No license: all rights reserved./; s/^\[!\[License\]\([^\n]*\n//m' "$dir/README.md"
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

# release_key_cmd OWNER OWNER/REPO: the command that copies the owner's stored
# release App key into the repo secret, for this platform (STANDARD.md
# section 2 has the matching store-once commands). Printed for the owner to
# run; the scripts never read the key themselves.
release_key_cmd() {
  local set="gh secret set RELEASE_APP_PRIVATE_KEY --repo $2"
  case "$(uname -s)" in
    Darwin) echo "security find-generic-password -s release-app-key -a $1 -w | base64 -d | $set" ;;
    MINGW*|MSYS*|CYGWIN*)
      printf '%s\n' "powershell.exe -NoProfile -Command \"[Net.NetworkCredential]::new('', (Import-Clixml '\$(cygpath -w ~/.config/repo-standard/release-app-key-$1.xml)')).Password.TrimEnd()\" | tr -d '\\r' | $set" ;;
    *) echo "secret-tool lookup service release-app-key account $1 | base64 -d | $set" ;;
  esac
}

# copy_tree SRC DST [--ignore-existing] [--delete] [--exclude /NAME]...
# Portable stand-in for `rsync -a SRC/ DST/`, because Git for Windows ships no
# rsync. Copies the contents of SRC (hidden files included) into DST, keeping
# modes, times and symlinks. --exclude names a top-level entry of SRC, like an
# anchored rsync pattern (`/src/` or `/_ci.yml`). --ignore-existing keeps files
# DST already has. --delete removes what SRC does not have (excluded entries
# are left alone, as rsync does). An entry whose type differs in DST (a file
# where SRC has a folder, or the reverse), or a folder that is a symlink in
# DST, is skipped with a note instead of being written through or stopping
# the copy halfway.
copy_tree() {
  local src="${1%/}" dst="${2%/}" keep=0 del=0 rel top e skip b list
  local -a excl=() blocked=()
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
  # List first, so a find error stops the copy instead of cutting it short.
  list="$(mktemp)"
  # find lists a folder before its contents, so folders exist before files.
  (cd "$src" && find . -mindepth 1 -print0) > "$list" ||
    { rm -f "$list"; die "copy_tree: cannot list $src"; }
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"; top="${rel%%/*}"; skip=0
    for e in ${excl[@]+"${excl[@]}"}; do [ "$top" = "$e" ] && skip=1; done
    for b in ${blocked[@]+"${blocked[@]}"}; do case "$rel" in "$b"/*) skip=1 ;; esac; done
    [ "$skip" = 1 ] && continue
    if [ -d "$src/$rel" ] && [ ! -L "$src/$rel" ]; then
      if [ -L "$dst/$rel" ] || { [ -e "$dst/$rel" ] && [ ! -d "$dst/$rel" ]; }; then
        echo "note: copy_tree skipped $rel/: the destination has a file or symlink there" >&2
        blocked+=("$rel")
        continue
      fi
      mkdir -p "$dst/$rel"
      continue
    fi
    if [ -d "$dst/$rel" ] && [ ! -L "$dst/$rel" ]; then
      echo "note: copy_tree skipped $rel: the destination has a folder there" >&2
      continue
    fi
    if [ "$keep" = 1 ] && { [ -e "$dst/$rel" ] || [ -L "$dst/$rel" ]; }; then continue; fi
    rm -f "$dst/$rel"  # replace a symlink instead of writing through it
    cp -Pp "$src/$rel" "$dst/$rel"
  done < "$list"
  if [ "$del" = 1 ]; then
    # Deepest first, so a folder is checked after everything inside it.
    (cd "$dst" && find . -mindepth 1 -depth -print0) > "$list" ||
      { rm -f "$list"; die "copy_tree: cannot list $dst"; }
    while IFS= read -r -d '' rel; do
      rel="${rel#./}"; top="${rel%%/*}"; skip=0
      for e in ${excl[@]+"${excl[@]}"}; do [ "$top" = "$e" ] && skip=1; done
      [ "$skip" = 1 ] && continue
      { [ -e "$src/$rel" ] || [ -L "$src/$rel" ]; } || rm -rf "${dst:?}/$rel"
    done < "$list"
  fi
  rm -f "$list"
}

# The stamp (ADR 0002): .github/repo-standard.yml in an adopted repo, with
# one "key: value" per line. Every script reads and writes it through these
# helpers, so they agree on comments, quotes and CRLF line ends.
# shellcheck disable=SC2034  # used by apply-overlay.sh, audit.sh and update-repo.sh
STAMP_FILE=.github/repo-standard.yml
# stamp_field FILE KEY: KEY's value, without a trailing comment, quotes or CR.
stamp_field() {
  [ -f "$1" ] || return 0
  K="$2" perl -ne 'if (/^\Q$ENV{K}\E:\s*(.*?)\s*$/) { my $v = $1; $v =~ s/\s+#.*$//;
    $v =~ s/^(["\x27])(.*)\1$/$2/; print "$v\n"; exit }' "$1"
}
# set_stamp_field FILE KEY VALUE: replace KEY's line, or append it when
# missing. Other lines, comments and line ends are kept.
set_stamp_field() {
  if grep -qE "^$2:" "$1" 2>/dev/null; then
    K="$2" V="$3" perl -pi -e 's/^\Q$ENV{K}\E:[^\r\n]*/$ENV{K}: $ENV{V}/' "$1"
  else
    printf '%s: %s\n' "$2" "$3" >> "$1"
  fi
}
# manifest_version DIR: the version in DIR/.release-please-manifest.json.
manifest_version() {
  sed -nE 's/.*"\."[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$1/.release-please-manifest.json" 2>/dev/null | head -n 1
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
# files, folders (ending in /), hooks (hook:<id>), .gitignore patterns
# (gitignore:<pattern>), Claude Code deny rules (claude-deny:<rule>) and audit
# rules (RS-AREA-NN, see docs/reference/audit-rules.md) the repo has chosen
# not to use. One entry per line; text after # is a comment (the reason).
EXCLUDE_FILE=.github/repo-standard-exclude
# exclude_entries FILE|-: the entries of an exclude list (- reads stdin), one
# per line, without comments or blanks. Read the list once and match with
# in_excludes.
exclude_entries() {
  [ "$1" = - ] || [ -f "$1" ] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep . || true
}
# in_excludes ENTRY LIST: true when ENTRY (a path or hook:<id>) is in LIST
# (from exclude_entries). A folder entry also covers every path inside it.
in_excludes() {
  local entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ "$1" = "$entry" ] && return 0
    case "$entry" in */) case "$1" in "$entry"*|"${entry%/}") return 0 ;; esac ;; esac
  done <<< "$2"
  return 1
}
# excluded DIR ENTRY: true when ENTRY is on DIR's exclude list.
excluded() { in_excludes "$2" "$(exclude_entries "$1/$EXCLUDE_FILE")"; }

# merge_gitignore FROM INTO REPO: append FROM's ignore patterns that INTO
# lacks and REPO's exclude list allows (gitignore:<pattern>), under one
# header. Comment and blank lines are not copied, so no empty section headers
# pile up, and a missing final newline in INTO is fixed first so the first
# new pattern does not join the last existing line.
merge_gitignore() {
  local from="$1" into="$2" excl line added=0
  excl="$(exclude_entries "$3/$EXCLUDE_FILE")"
  touch "$into"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    grep -qxF -- "$line" "$into" && continue
    in_excludes "gitignore:$line" "$excl" && continue
    if [ "$added" = 0 ]; then
      [ -s "$into" ] && [ -n "$(tail -c 1 "$into")" ] && echo >> "$into"
      grep -qxF "# Added by the repo standard" "$into" ||
        { [ -s "$into" ] && echo >> "$into"; echo "# Added by the repo standard" >> "$into"; }
      added=1
    fi
    echo "$line" >> "$into"
  done < "$from"
}

# origin_slug DIR: OWNER/NAME of DIR's GitHub origin remote, or nothing.
origin_slug() {
  git -C "$1" remote get-url origin 2>/dev/null |
    sed -nE 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//' || true
}

# pytest_mode PYPROJECT: how pyproject.toml configures pytest 9 strict mode:
# "strict", "loose", "invalid" (not valid TOML), "no-python", or nothing
# when the file is missing or does not configure pytest.
pytest_mode() {
  [ -f "$1" ] || return 0
  python3 -c '
import re, sys
TRUE = ("true", "yes", "on", "1")
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None
if tomllib is None:
    # Python 3.9 and 3.10 without tomli: read the two pytest tables line
    # by line (enough for the plain key = value lines pytest config uses).
    table, seen, strict = "", False, False
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        head = re.match(r"\s*\[([^\]]+)\]\s*(#.*)?$", line)
        if head:
            table = head.group(1).replace(" ", "")
            seen = seen or table in ("tool.pytest", "tool.pytest.ini_options")
            continue
        value = re.match(r"\s*strict\s*=\s*[\x27\x22]?(\w+)", line)
        if table in ("tool.pytest", "tool.pytest.ini_options") and value:
            strict = strict or value.group(1).lower() in TRUE
    sys.exit(print("strict" if strict else "loose") if seen else None)
try:
    with open(sys.argv[1], "rb") as f:
        tool = tomllib.load(f).get("tool", {})
except (OSError, ValueError):
    sys.exit(print("invalid"))
pytest = tool.get("pytest")
if isinstance(pytest, dict):
    for table in (pytest, pytest.get("ini_options")):
        # pytest reads an ini boolean as true from any of these spellings.
        if isinstance(table, dict) and str(table.get("strict", "")).lower() in TRUE:
            sys.exit(print("strict"))
    print("loose")' "$1" 2>/dev/null | tr -d '\r' || echo no-python
}
