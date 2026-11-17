#!/usr/bin/env bash
# Usage: sync-pins.sh [--check | --latest [--as LOGIN]]
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
#              least 7 days old (the Dependabot cooldown) and newer than the
#              pin. Needs gh; reads GitHub as LOGIN (default: the owner of
#              this clone's origin remote).
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
cd "$STANDARD_ROOT" || exit 1

mode=sync; as=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--latest)
      [ "$mode" = sync ] || die "--check and --latest cannot be combined"
      mode="${1#--}" ;;
    --as) as="${2:?--as needs a login}"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

files="$(git ls-files -- '.github/workflows/*.yml' '.pre-commit-config.yaml' \
  'template/.github/workflows/*.yml' 'template/.pre-commit-config.yaml' \
  'overlays/*.yml' 'overlays/*.yaml')"

# The pin table: one line per pin, "KIND KEY SHA COMMENT FILE", where KIND is
# action (KEY owner/repo) or hook (KEY the repo URL), and COMMENT is the tag
# comment or "-".
table() {
  # shellcheck disable=SC2086
  python3 - $files <<'PY'
import re, sys
for path in sys.argv[1:]:
    lines = open(path, encoding="utf-8").read().split("\n")
    for i, line in enumerate(lines):
        m = re.search(r"uses: ([\w.-]+/[\w.-]+)(?:/[^@\s]*)?@([0-9a-f]{40})(?:[ \t]+#[ \t]*(\S+))?", line)
        if m:
            print("action", m.group(1), m.group(2), m.group(3) or "-", path)
        m = re.match(r"\s*-\s*repo:\s*(https://\S+)\s*$", line)
        if m and i + 1 < len(lines):
            r = re.match(r"\s*rev:\s*([0-9a-f]{40})[ \t]*(?:#[ \t]*frozen:[ \t]*(\S+))?", lines[i + 1])
            if r:
                print("hook", m.group(1), r.group(1), r.group(2) or "-", path)
PY
}
tbl="$(table)"
is_root() { case "$1" in .pre-commit-config.yaml|.github/workflows/*) return 0 ;; esac; return 1; }

if [ "$mode" = check ]; then
  bad="$(printf '%s\n' "$tbl" | awk '{ key = $1 " " $2; if (!(key in sha)) sha[key] = $3; else if (sha[key] != $3) print key }' | sort -u)"
  if [ -n "$bad" ]; then
    echo "drift: pinned to more than one commit:"
    printf '%s\n' "$bad" | sed 's/^/  /'
    echo "run scripts/sync-pins.sh; for a pin no root file has, run scripts/sync-pins.sh --latest"
    exit 1
  fi
  exit 0
fi

# Target pins: root pins first (one commit per key, or stop), then (with
# --latest) releases for the rest.
root_pins="$(printf '%s\n' "$tbl" | while read -r k key sha c f; do is_root "$f" && echo "$k $key $sha $c"; done || true)"
split="$(printf '%s\n' "$root_pins" | awk 'NF { print $1, $2, $3 }' | sort -u | awk '{ print $1, $2 }' | uniq -d)"
[ -z "$split" ] || die "the root files pin $(echo "$split" | tr '\n' ' ')to different commits; make them agree first"
# One line per key: the first tag comment that is not "-".
targets="$(printf '%s\n' "$root_pins" | awk 'NF { k = $1 " " $2; if (!(k in s)) { s[k] = $3; c[k] = $4; o[++n] = k } else if (c[k] == "-") c[k] = $4 }
  END { for (i = 1; i <= n; i++) print o[i], s[o[i]], c[o[i]] }')"

if [ "$mode" = latest ]; then
  if [ -z "$as" ]; then slug="$(origin_slug "$STANDARD_ROOT")"; as="${slug%%/*}"; fi
  [ -n "$as" ] || die "no GitHub origin remote: pass --as LOGIN"
  cutoff="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  # latest_release OWNER/REPO: "SHA TAG" of the newest non-draft,
  # non-prerelease release published before the cutoff.
  latest_release() {
    local tag sha
    tag="$(gh_as "$as" api "repos/$1/releases?per_page=30" --jq \
      "[.[] | select(.draft | not) | select(.prerelease | not) | select(.published_at <= \"$cutoff\")][0].tag_name // empty")"
    [ -n "$tag" ] || return 1
    sha="$(gh_as "$as" api "repos/$1/commits/$tag" --jq .sha)" || return 1
    echo "$sha $tag"
  }
  others="$(printf '%s\n' "$tbl" | awk 'NF { print $1, $2 }' | sort -u | while read -r kind key; do
    printf '%s\n' "$targets" | awk -v k="$kind" -v key="$key" '$1 == k && $2 == key { f = 1 } END { exit !f }' && continue
    repo="$key"; [ "$kind" = hook ] && repo="$(echo "$key" | sed -E 's#^https://github\.com/##; s#\.git$##')"
    if ! rel="$(latest_release "$repo")"; then
      echo "warning: no release of $repo older than 7 days; $key left as is" >&2; continue
    fi
    # Never move a pin backwards: every current pin must be behind the release.
    newer=1
    for cur in $(printf '%s\n' "$tbl" | awk -v k="$kind" -v key="$key" '$1 == k && $2 == key { print $3 }' | sort -u); do
      [ "$cur" = "${rel%% *}" ] && continue
      st="$(gh_as "$as" api "repos/$repo/compare/$cur...${rel%% *}" --jq .status 2>/dev/null || true)"
      [ "$st" = ahead ] || { newer=0; break; }
    done
    if [ "$newer" = 1 ]; then echo "$kind $key $rel"
    else echo "warning: $key is not behind ${rel#* } (or the comparison failed); left as is" >&2; fi
  done)"
  targets="$(printf '%s\n%s\n' "$targets" "$others" | grep . || true)"
fi

changed=0
while read -r kind key sha comment; do
  [ -n "$kind" ] || continue
  for f in $(printf '%s\n' "$tbl" | awk -v k="$kind" -v key="$key" -v sha="$sha" '$1 == k && $2 == key && $3 != sha { print $5 }' | sort -u); do
    before="$(cksum < "$f")"
    KIND="$kind" KEY="$key" SHA="$sha" TAG="$comment" perl -0pi -e '
      my ($k, $key, $sha, $tag) = @ENV{qw(KIND KEY SHA TAG)};
      my $c = $tag eq "-" ? "" : $tag;
      # The new pin takes the target tag comment, or none: an old comment
      # would name the wrong version. [ \t] keeps matches on one line.
      if ($k eq "action") {
        s{(uses:[ \t]+\Q$key\E(?:/[^@\s]*)?\@)[0-9a-f]{40}(?:[ \t]+#[ \t]*\S+)?}{$1 . $sha . (length $c ? " # $c" : "")}ge;
      } else {
        s{(-[ \t]*repo:[ \t]*\Q$key\E[ \t]*\n[ \t]*rev:[ \t]*)[0-9a-f]{40}(?:[ \t]*#[ \t]*frozen:[ \t]*\S+)?}{$1 . $sha . (length $c ? "  # frozen: $c" : "")}ge;
      }' "$f"
    if [ "$(cksum < "$f")" != "$before" ]; then
      echo "pinned $key to ${comment/#-/$sha} in $f"; changed=$((changed + 1))
    else
      echo "warning: could not rewrite the $key pin in $f; fix it by hand" >&2
    fi
  done
done <<< "$targets"
[ "$changed" -gt 0 ] || echo "all pins already match"
