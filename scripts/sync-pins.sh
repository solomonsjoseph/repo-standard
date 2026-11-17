#!/usr/bin/env bash
# Usage: sync-pins.sh [--check] [--latest]
#
# Keeps action SHAs and pre-commit hook revisions the same everywhere in
# repo-standard. Dependabot updates only the root files
# (.github/workflows/*.yml and .pre-commit-config.yaml); template/ and
# overlays/ hold copies of the same pins, plus pins of their own.
#
#   (default)  copy every root pin to the same action or hook repository in
#              template/ and overlays/.
#   --check    change nothing; exit 1 when an action or hook repository is
#              pinned to more than one commit (check-drift.sh runs this).
#   --latest   also move pins that exist only in template/ or overlays/,
#              which Dependabot never sees, to the newest release that is at
#              least 7 days old (the Dependabot cooldown). Needs gh.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
cd "$STANDARD_ROOT" || exit 1

mode=sync
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check ;;
    --latest) mode=latest ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

# latest_release OWNER/REPO: "SHA TAG" of the newest non-draft, non-prerelease
# release published at least 7 days ago.
latest_release() {
  local cutoff tag sha
  cutoff="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  tag="$(gh api "repos/$1/releases?per_page=30" --jq \
    "[.[] | select(.draft | not) | select(.prerelease | not) | select(.published_at <= \"$cutoff\")][0].tag_name // empty")"
  [ -n "$tag" ] || return 1
  sha="$(gh api "repos/$1/commits/$tag" --jq .sha)" || return 1
  echo "$sha $tag"
}

files="$(git ls-files -- '.github/workflows/*.yml' '.pre-commit-config.yaml' \
  'template/.github/workflows/*.yml' 'template/.pre-commit-config.yaml' \
  'overlays/*.yml' 'overlays/*.yaml')"

# The pin table: one line per pin, "KIND KEY SHA COMMENT FILE", where KIND is
# action (KEY owner/repo) or hook (KEY the repo URL).
table() {
  # shellcheck disable=SC2086
  python3 - $files <<'PY'
import re, sys
for path in sys.argv[1:]:
    lines = open(path, encoding="utf-8").read().split("\n")
    for i, line in enumerate(lines):
        m = re.search(r"uses: ([\w.-]+/[\w.-]+)(?:/[^@\s]*)?@([0-9a-f]{40})(?:\s+#\s*(\S+))?", line)
        if m:
            print("action", m.group(1), m.group(2), m.group(3) or "-", path)
        m = re.match(r"\s*-\s*repo:\s*(https://\S+)\s*$", line)
        if m and i + 1 < len(lines):
            r = re.match(r"\s*rev:\s*([0-9a-f]{40})\s*(?:#\s*frozen:\s*(\S+))?", lines[i + 1])
            if r:
                print("hook", m.group(1), r.group(1), r.group(2) or "-", path)
PY
}

if [ "$mode" = check ]; then
  bad="$(table | awk '{ key = $1 " " $2; if (!(key in sha)) sha[key] = $3; else if (sha[key] != $3) print key }' | sort -u)"
  if [ -n "$bad" ]; then
    echo "drift: pinned to more than one commit (run scripts/sync-pins.sh):"
    printf '  %s\n' "$bad"
    exit 1
  fi
  exit 0
fi

# Target pins: root pins first, then (with --latest) releases for the rest.
targets="$(table | awk '$5 == ".pre-commit-config.yaml" || $5 ~ /^\.github\/workflows\// { print $1, $2, $3, $4 }' | sort -u)"
split="$(printf '%s\n' "$targets" | awk '{ print $1, $2 }' | uniq -d)"
[ -z "$split" ] || die "the root files pin $(echo "$split" | tr '\n' ' ')to different commits; make them agree first"
if [ "$mode" = latest ]; then
  others="$(table | awk '{ print $1, $2 }' | sort -u | while read -r kind key; do
    printf '%s\n' "$targets" | grep -q "^$kind $key " && continue
    repo="$key"; [ "$kind" = hook ] && repo="$(echo "$key" | sed -E 's#^https://github\.com/##; s#\.git$##')"
    if rel="$(latest_release "$repo")"; then
      echo "$kind $key $rel"
    else
      echo "warning: no release of $repo older than 7 days; $key left as is" >&2
    fi
  done)"
  targets="$(printf '%s\n%s\n' "$targets" "$others" | grep . || true)"
fi

changed=0
while read -r kind key sha comment; do
  [ -n "$kind" ] || continue
  for f in $(table | awk -v k="$kind" -v key="$key" -v sha="$sha" '$1 == k && $2 == key && $3 != sha { print $5 }' | sort -u); do
    KIND="$kind" KEY="$key" SHA="$sha" TAG="$comment" perl -0pi -e '
      my ($k, $key, $sha, $tag) = @ENV{qw(KIND KEY SHA TAG)};
      if ($k eq "action") {
        s{(uses:\s+\Q$key\E(?:/[^@\s]*)?\@)[0-9a-f]{40}(\s+#\s*)\S+}{$1$sha$2$tag}g;
        s{(uses:\s+\Q$key\E(?:/[^@\s]*)?\@)[0-9a-f]{40}(?!\s+#)}{$1$sha # $tag}g;
      } else {
        s{(-\s*repo:\s*\Q$key\E\s*\n\s*rev:\s*)[0-9a-f]{40}(\s*#\s*frozen:\s*)\S+}{$1$sha$2$tag}g;
      }' "$f"
    echo "pinned $key to $comment in $f"; changed=$((changed + 1))
  done
done <<< "$targets"
[ "$changed" -gt 0 ] || echo "all pins already match"
