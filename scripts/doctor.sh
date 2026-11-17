#!/usr/bin/env bash
# Usage: doctor.sh [OWNER]...
# Read-only check that this machine can run the repo-standard scripts: the
# tools and their versions, the private per-owner config, the gh logins, and
# (on Windows) the settings that break hooks. With no OWNER it checks every
# OWNER.env in the config folder. Exits 1 when a required item fails.
# The config files are sourced only inside subshells, so nothing they set
# leaks into this script.
# shellcheck disable=SC2031
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

fails=0; warns=0
pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# ver_ge A B: true when version A is at least version B (numeric parts only).
ver_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, "."); k = (n > m) ? n : m
    for (i = 1; i <= k; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 0 }'
}
# version_of CMD...: first dotted version number in the command's output.
version_of() { "$@" 2>&1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }

windows=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) windows=1 ;; esac

echo "== tools"
if ver_ge "${BASH_VERSION%%[^0-9.]*}" 3.2; then pass "bash $BASH_VERSION"; else fail "bash $BASH_VERSION is older than 3.2"; fi
for t in git gh perl jq find awk cmp diff mktemp; do
  if command -v "$t" >/dev/null; then pass "$t"; else fail "$t not found (required)"; fi
done
# Windows can resolve python3 to a Microsoft Store stub that only prints a
# message, so run it rather than only looking it up.
if python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
  pass "python3 $(version_of python3 --version)"
else
  fail "python3 3.9 or later not runnable (audit.sh and the check-docs hook need it)"
fi
v="$(version_of pre-commit --version || true)"
if [ -z "$v" ]; then fail "pre-commit not found: uv tool install pre-commit"
elif ver_ge "$v" 4.7; then pass "pre-commit $v"
else fail "pre-commit $v is older than 4.7 (fails with current npm): uv tool upgrade pre-commit"; fi
for t in uv:python pnpm:ts shellcheck:"linting scripts outside pre-commit"; do
  if command -v "${t%%:*}" >/dev/null; then pass "${t%%:*}"; else warn "${t%%:*} not found (needed for ${t#*:})"; fi
done

echo "== config ($CONFIG_DIR)"
if [ -d "$CONFIG_DIR" ]; then pass "config folder exists"; else fail "no $CONFIG_DIR (see scripts/lib.sh)"; fi
src_owner="$( (REPO_STANDARD_SOURCE_OWNER=""
  # shellcheck disable=SC1091
  [ -f "$CONFIG_DIR/source.env" ] && source "$CONFIG_DIR/source.env"; echo "$REPO_STANDARD_SOURCE_OWNER") )"
if [ -n "$src_owner" ]; then pass "source.env names the source owner ($src_owner)"
else fail "set REPO_STANDARD_SOURCE_OWNER in $CONFIG_DIR/source.env"; fi

owners=("$@")
if [ ${#owners[@]} -eq 0 ]; then
  for f in "$CONFIG_DIR"/*.env; do
    [ -f "$f" ] || continue
    b="$(basename "$f" .env)"; [ "$b" = source ] || owners+=("$b")
  done
fi
[ ${#owners[@]} -gt 0 ] || fail "no OWNER.env files in $CONFIG_DIR"

for o in ${owners[@]+"${owners[@]}"}; do
  echo "== owner $o"
  conf="$CONFIG_DIR/$o.env"
  if [ ! -f "$conf" ]; then fail "no $conf"; continue; fi
  # Subshell: load_owner exits through die on a bad file.
  vals="$( (load_owner "$o" && printf '%s\037%s\037%s' "$OWNER_NAME" "$RELEASE_APP_CLIENT_ID" "$SIGNING_KEY") 2>&1)" ||
    { fail "$vals"; continue; }
  # A non-whitespace separator, so an empty middle field is not collapsed.
  IFS=$'\037' read -r name client key <<<"$vals"
  pass "OWNER_NAME=$name"
  if [ -n "$client" ]; then pass "release App client id set"
  else warn "no RELEASE_APP_CLIENT_ID: release-please reports 'not configured' until it is set"; fi
  if [ -z "$key" ]; then warn "no SIGNING_KEY: commits are unsigned"
  elif [ -f "${key/#\~/$HOME}" ]; then pass "signing key ${key}"
  else fail "SIGNING_KEY ${key} does not exist"; fi
  if gh auth token --user "$o" >/dev/null 2>&1; then pass "gh login for $o"
  else fail "no gh login for $o: gh auth login (as $o)"; fi
done

echo "== machine setup (scripts/setup-machine.sh)"
tpl_dir="$(git config --global --get init.templateDir || true)"
if [ -n "$tpl_dir" ] && cmp -s "$STANDARD_ROOT/scripts/git-hooks/pre-push" "$tpl_dir/hooks/pre-push"; then
  pass "pre-push guard in the git template ($tpl_dir)"
else
  warn "pre-push guard not in the git template: run scripts/setup-machine.sh"
fi
claude_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if grep -qs "git-identity-switch.sh" "$claude_settings"; then
  pass "Claude Code identity hook registered"
else
  warn "Claude Code identity hook not registered: run scripts/setup-machine.sh"
fi
if [ -f "$CONFIG_DIR/act-as" ]; then
  acting="$(act_as_account)"
  if [ -f "$CONFIG_DIR/$acting.env" ]; then pass "every repository acts as $acting (act-as)"
  else fail "act-as names $acting, but $CONFIG_DIR/$acting.env does not exist"; fi
fi

if [ "$windows" = 1 ]; then
  echo "== windows"
  # Repos carry '* text=auto eol=lf', which wins over core.autocrlf, but a
  # folder without that file gets CRLF scripts that bash cannot run.
  if [ "$(git config --get core.autocrlf || true)" = true ]; then
    warn "core.autocrlf=true: fine inside standard repos (.gitattributes forces LF); elsewhere shell scripts check out with CRLF"
  else pass "core.autocrlf is not true"; fi
  # Smart App Control blocks the unsigned binaries pre-commit downloads or
  # builds (Vale, gitleaks, actionlint, compiled Python extensions).
  sac="$(powershell.exe -NoProfile -Command "(Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\CI\\Policy' -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState" 2>/dev/null | tr -d '\r')"
  case "$sac" in
    1) warn "Smart App Control is on: it blocks hooks that pre-commit builds (vale, gitleaks, actionlint, check-yaml). Run hooks in WSL, or rely on CI for those hooks" ;;
    2) warn "Smart App Control is in evaluation mode and may turn on and block hook binaries" ;;
    *) pass "Smart App Control is off" ;;
  esac
fi

echo "== $fails failed, $warns warnings"
[ "$fails" = 0 ]
