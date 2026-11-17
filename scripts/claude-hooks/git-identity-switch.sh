#!/usr/bin/env bash
# Claude Code PreToolUse hook for the Bash and PowerShell tools, installed by
# scripts/setup-machine.sh. Before a git command runs inside a GitHub clone,
# it makes that clone's local commit identity and credential helper match the
# account that should act there, using set_identity from lib.sh:
#   - the account named in ~/.config/repo-standard/act-as, when that file
#     exists (one account acts in every repository, for example as a
#     collaborator on another account's repositories);
#   - otherwise the owner in the clone's origin URL.
# A commit or push in a clone whose account has no OWNER.env is blocked
# (exit 2), because it would go out under an unknown identity. Global git
# config is never touched, and `gh auth switch` is never run.
#
# Reads the hook input (JSON) on stdin. Exit 0 lets the command run; exit 2
# blocks it and shows stderr to Claude. Anything unexpected exits 0 quietly:
# this hook fixes identities, it is not a gate for unrelated commands.

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
set +e

input="$(cat)"
read_field() { printf '%s' "$input" | python3 -c '
import json, sys
d = json.load(sys.stdin)
v = d
for k in sys.argv[1].split("."):
    v = v.get(k, "") if isinstance(v, dict) else ""
print(v)' "$1" 2>/dev/null; }

cmd="$(read_field tool_input.command)"
cwd="$(read_field cwd)"
case "$cmd" in *git*) ;; *) exit 0 ;; esac

# The repository the command runs in: `git -C DIR` or a leading `cd DIR &&`,
# else the session's working directory.
dir="$cwd"
if [[ "$cmd" =~ git[[:space:]]+-C[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:]]+) ]] ||
   [[ "$cmd" =~ ^[[:space:]]*cd[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:]\;\&]+) ]]; then
  d="${BASH_REMATCH[1]}"; d="${d%\"}"; d="${d#\"}"; d="${d%\'}"; d="${d#\'}"
  case "$d" in /*|[A-Za-z]:*|~*) dir="${d/#\~/$HOME}" ;; *) dir="$cwd/$d" ;; esac
fi
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
url="$(git -C "$top" remote get-url origin 2>/dev/null)" || exit 0
[[ "$url" =~ github\.com[:/]([^/]+)/ ]] || exit 0
owner="${BASH_REMATCH[1]}"

account="$(act_as_account)"; account="${account:-$owner}"

if [ ! -f "$CONFIG_DIR/$account.env" ]; then
  # git, then any global options (-C DIR, quoted or not, -c KEY=VALUE,
  # --no-pager, --git-dir=...), then commit or push.
  git_write_re='(^|[;&|({[:space:]])git([[:space:]]+(-[Cc][[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)|--[^[:space:]]+|-[A-Za-z]))*[[:space:]]+(commit|push)([[:space:]]|$)'
  if [[ "$cmd" =~ $git_write_re ]]; then
    echo "git-identity-switch: no $CONFIG_DIR/$account.env, so $top has no known identity for '$account'. Create it (see scripts/lib.sh) before committing or pushing." >&2
    exit 2
  fi
  exit 0
fi

# Already right: same name, the account's noreply address, and a credential
# helper that answers as the account. Checked locally, so no network call.
name="$( (owner_name "$account") 2>/dev/null)"
if [ "$(git -C "$top" config --local user.name)" = "$name" ] &&
   [[ "$(git -C "$top" config --local user.email)" == *"+$account@users.noreply.github.com" ]] &&
   git -C "$top" config --local --get-all credential.https://github.com.helper | grep -q "username=$account;"; then
  exit 0
fi

if (set_identity "$top" "$account") >/dev/null 2>&1; then
  echo "git-identity-switch: set $top to act as $account" >&2
else
  echo "git-identity-switch: could not set the identity for $account in $top (is gh logged in as $account?)" >&2
fi
exit 0
