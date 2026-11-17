#!/usr/bin/env bash
# Usage: new-repo.sh OWNER NAME OVERLAY public|private --license SPDX|none
#          [--addon api-http|api-events|sensitive-data]... [--desc TEXT] [--dir PARENT]
# Creates a repository that follows STANDARD.md:
#   1. builds it locally from template/ plus the language overlay (and the
#      public overlay for public repos), with placeholders filled in;
#   2. adds the chosen license;
#   3. makes the single bootstrap commit on main and pushes it;
#   4. runs apply-settings.sh (merge options, security, labels, ruleset).
# The release App key is never handled here; the next steps are printed.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

owner="${1:?owner}"; name="${2:?name}"; overlay="${3:?overlay}"; vis="${4:?public|private}"; shift 4
license=""; desc="$name"; parent="$PWD"; addons=()
while [ $# -gt 0 ]; do
  case "$1" in
    --license) license="$2"; shift ;;
    --addon) addons+=("$2"); shift ;;
    --desc) desc="$2"; shift ;;
    --dir) parent="$2"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
load_owner "$owner"
[ -n "$license" ] || die "--license is required (an SPDX id such as apache-2.0 or mit, or none)"
case "$vis" in public|private) ;; *) die "visibility must be public or private" ;; esac
[ -d "$STANDARD_ROOT/overlays/$overlay" ] || die "unknown overlay $overlay"
dir="$parent/$name"
[ -e "$dir" ] && die "$dir already exists"
gh_as "$owner" repo view "$owner/$name" >/dev/null 2>&1 && die "$owner/$name already exists on GitHub"

info "building $dir"
mkdir -p "$dir"
copy_tree "$STANDARD_ROOT/template" "$dir"
pub_flag=(); [ "$vis" = public ] && pub_flag=(--public)
"$STANDARD_ROOT/scripts/apply-overlay.sh" "$dir" "$overlay" ${pub_flag[@]+"${pub_flag[@]}"} \
  --owner "$owner" --name "$name" --desc "$desc"
for addon in ${addons[@]+"${addons[@]}"}; do
  "$STANDARD_ROOT/scripts/apply-overlay.sh" "$dir" "$addon" \
    --owner "$owner" --name "$name" --desc "$desc"
done

write_license "$dir" "$owner" "$license"
make_locks "$dir" "$overlay"

info "bootstrap commit"
git -C "$dir" init -q -b main
set_identity "$dir" "$owner"
git -C "$dir" add -A
git -C "$dir" commit -q -m "chore: bootstrap from repo-standard" \
  -m "Base template plus the $overlay overlay from repo-standard."

info "creating $owner/$name ($vis)"
gh_as "$owner" repo create "$owner/$name" "--$vis" --description "$desc" \
  --source "$dir" --remote origin --push

"$STANDARD_ROOT/scripts/apply-settings.sh" "$owner/$name" "$vis"

key_cmd="$(release_key_cmd "$owner" "$owner/$name")"
cat <<NEXT

Done: https://github.com/$owner/$name

Next steps (you, not Claude):
  1. Install the release App on this repo: https://github.com/settings/installations
  2. $key_cmd
     (store the key once first; see STANDARD.md section 2)
  3. cd $dir && pre-commit install --hook-type pre-commit --hook-type commit-msg
NEXT
