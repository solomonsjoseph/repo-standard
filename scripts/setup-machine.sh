#!/usr/bin/env bash
# Usage: setup-machine.sh [--act-as OWNER|none] [--force]
# One-time setup of a machine for the standard. Safe to re-run; it prints
# every change it makes and changes nothing that is already right.
#   1. Copies scripts/git-hooks/ to CONFIG_DIR/git-template/hooks/ and points
#      the global init.templateDir at it, so every new clone and `git init`
#      gets the pre-push guard. Refuses to replace a different existing
#      init.templateDir unless --force is given.
#   2. --act-as OWNER makes that one account act in every repository (the
#      identity hook reads CONFIG_DIR/act-as); --act-as none removes the file.
#   3. Registers scripts/claude-hooks/git-identity-switch.sh as a Claude Code
#      PreToolUse hook in the user settings (~/.claude/settings.json, or
#      $CLAUDE_CONFIG_DIR), after a backup, replacing any older entry for it.
#   4. Runs doctor.sh.
# It never creates OWNER.env or source.env (they hold private choices; see
# scripts/lib.sh) and never runs `gh auth switch`. Existing clones get the
# pre-push guard by running `git init` inside each clone; git init never
# replaces a pre-push hook a clone already has, so copy it by hand there.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

act_as=""; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --act-as) act_as="${2:?--act-as needs OWNER or none}"; shift ;;
    --force) force=1 ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

# native_path PATH: the form native Windows programs (git.exe, Claude Code)
# read; unchanged elsewhere.
native_path() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }

mkdir -p "$CONFIG_DIR"

info "git template hooks"
tpl="$CONFIG_DIR/git-template"
mkdir -p "$tpl/hooks"
for h in "$STANDARD_ROOT"/scripts/git-hooks/*; do
  dst="$tpl/hooks/$(basename "$h")"
  if ! cmp -s "$h" "$dst"; then cp "$h" "$dst"; chmod +x "$dst"; echo "updated $dst"; fi
done
want="$(native_path "$tpl")"
have="$(git config --global --get init.templateDir || true)"
if [ "$have" = "$want" ]; then
  echo "init.templateDir already set"
elif [ -n "$have" ] && [ "$force" = 0 ]; then
  die "init.templateDir is already $have; re-run with --force to replace it with $want"
else
  git config --global init.templateDir "$want"
  echo "set init.templateDir=$want"
fi

if [ -n "$act_as" ]; then
  info "acting account"
  if [ "$act_as" = none ]; then
    rm -f "$CONFIG_DIR/act-as"; echo "removed $CONFIG_DIR/act-as"
  else
    load_owner "$act_as"
    echo "$act_as" > "$CONFIG_DIR/act-as"; echo "every repository acts as $act_as"
  fi
fi

info "Claude Code identity hook"
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
mkdir -p "$(dirname "$settings")"
# The full path of this bash: on Windows a bare `bash` can resolve to WSL's
# bash.exe, which cannot run a C:/ path or the Windows python3 and gh.
bash_bin="$BASH"; [ -f "$bash_bin.exe" ] && bash_bin="$bash_bin.exe"
hook_cmd="\"$(native_path "$bash_bin")\" \"$(native_path "$STANDARD_ROOT/scripts/claude-hooks/git-identity-switch.sh")\""
SETTINGS="$settings" HOOK_CMD="$hook_cmd" python3 - <<'PY'
import json, os, shutil
path, cmd = os.environ["SETTINGS"], os.environ["HOOK_CMD"]
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
groups = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
entry = {"matcher": "Bash|PowerShell",
         "hooks": [{"type": "command", "command": cmd, "timeout": 30}]}
mine = [g for g in groups
        if any("git-identity-switch.sh" in h.get("command", "") for h in g.get("hooks", []))]
if mine == [entry]:
    print("already registered in " + path)
else:
    for g in groups:
        g["hooks"] = [h for h in g.get("hooks", [])
                      if "git-identity-switch.sh" not in h.get("command", "")]
    groups[:] = [g for g in groups if g.get("hooks")]
    groups.append(entry)
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak-repo-standard")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("registered in " + path + " (backup: settings.json.bak-repo-standard)")
PY

info "checking the machine"
"$STANDARD_ROOT/scripts/doctor.sh" || true
echo
echo "Existing clones get the pre-push guard by running 'git init' inside each clone."
echo "A clone that already has a pre-push hook keeps it: copy scripts/git-hooks/pre-push into its .git/hooks/ by hand."
