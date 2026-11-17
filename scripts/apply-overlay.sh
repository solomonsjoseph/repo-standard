#!/usr/bin/env bash
# Usage: apply-overlay.sh TARGET_DIR OVERLAY --owner O [--name N] [--desc D] [--public] [--retrofit]
#          [--codeql-langs "L1 L2"]
#
# Applies a language overlay (python, ts, go, r, swift, docs) or an add-on
# overlay (api-http, api-events) to a repo, plus the public overlay when
# --public is set. Placeholders (__OWNER__, __REPO_NAME__, ...) are filled in.
#
# Default mode (new repos): TARGET_DIR already holds template/; overlay files
# are copied over it and the fragments below are merged in.
#
# --retrofit (existing repos): nothing that exists is overwritten. Missing
# base-template and overlay files are copied in, sample source code is
# skipped, and any fragment that cannot be merged automatically is written to
# .scratch/repo-standard-merge/ for a hand merge.
#
# Overlay files starting with "_" are merge fragments:
#   _ci.yml         replaces .github/workflows/ci.yml
#   _precommit.yaml appended to .pre-commit-config.yaml
#   _dependabot.yml appended to .github/dependabot.yml
#   _gitignore      lines added to .gitignore
#   _release-type   sets release-type in release-please-config.json
#   _codeql-langs   CodeQL languages for the public overlay
#
# --codeql-langs "L1 L2" sets the CodeQL languages explicitly (for example
# "actions python javascript-typescript"). Without it, a retrofit adds every
# language it finds in the repo's tracked files to the overlay's list.
#
# Retrofits also turn on Dependabot alerts (so dependency-review can run on the
# adoption PR) and warn about tracked symlinks, which usually break in CI.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

target="${1:?target dir}"; overlay="${2:?overlay}"; shift 2
public=0; retrofit=0; owner=""; name=""; desc=""; codeql_langs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --public) public=1 ;;
    --retrofit) retrofit=1 ;;
    --codeql-langs) codeql_langs="$2"; shift ;;
    --owner) owner="$2"; shift ;;
    --name) name="$2"; shift ;;
    --desc) desc="$2"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
[ -n "$owner" ] || die "--owner is required (placeholders would stay unfilled)"
src="$STANDARD_ROOT/overlays/$overlay"
[ -d "$src" ] || die "no overlay '$overlay' (see $STANDARD_ROOT/overlays)"
# A language overlay (python, ts, ...) carries a _release-type; any other
# overlay is an add-on (api-http, ...). Every kind-dependent step uses this.
kind=addon; [ -f "$src/_release-type" ] && kind=language
[ -d "$target" ] || die "$target does not exist"
[ "$retrofit" = 1 ] || [ -f "$target/.pre-commit-config.yaml" ] || die "$target has no base template"
name="${name:-$(basename "$target")}"
desc="${desc:-$name}"
pkg="$(echo "$name" | tr '[:upper:]-' '[:lower:]_')"
case "$overlay" in swift|r) pkg="$(echo "$name" | perl -pe 's/(^|[-_])(\w)/\U$2/g')" ;; esac

fragments=(--exclude /_ci.yml --exclude /_precommit.yaml --exclude /_dependabot.yml
  --exclude /_gitignore --exclude /_release-type --exclude /_codeql-langs
  --exclude /_agents.md)
merge_dir="$target/.scratch/repo-standard-merge/$overlay"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT

# Stage everything this overlay would add, with placeholders filled in.
[ "$retrofit" = 1 ] && copy_tree "$STANDARD_ROOT/template" "$stage"
copy_tree "$src" "$stage" "${fragments[@]}"
# detect_codeql_langs DIR: CodeQL languages found in DIR's tracked files.
detect_codeql_langs() {
  git -C "$1" ls-files 2>/dev/null | awk -F. 'NF > 1 { print tolower($NF) }' | sort -u |
    while read -r ext; do
      case "$ext" in
        py) echo python ;;
        js|jsx|mjs|cjs|ts|tsx|mts|cts|vue) echo javascript-typescript ;;
        go) echo go ;;
        swift) echo swift ;;
        java|kt|kts) echo java-kotlin ;;
        cs) echo csharp ;;
        c|cc|cpp|cxx|h|hpp) echo c-cpp ;;
        rb) echo ruby ;;
        rs) echo rust ;;
      esac
    done | sort -u
}

if [ "$public" = 1 ] && [ -f "$src/_codeql-langs" ]; then
  copy_tree "$STANDARD_ROOT/overlays/public" "$stage"
  if [ -n "$codeql_langs" ]; then
    lang_list="$codeql_langs"
  else
    lang_list="$(cat "$src/_codeql-langs")"
    if [ "$retrofit" = 1 ]; then
      for l in $(detect_codeql_langs "$target"); do
        case " $lang_list " in *" $l "*) ;; *)
          lang_list="$lang_list $l"
          echo "note: CodeQL also scans $l (found in tracked files; override with --codeql-langs)" ;;
        esac
      done
    fi
  fi
  langs="$(echo "$lang_list" | tr ' ' '\n' | grep . | paste -sd, - | sed 's/,/, /g')"
  LANGS="$langs" perl -pi -e 's/__CODEQL_LANGS__/$ENV{LANGS}/' "$stage/.github/workflows/codeql.yml"
fi
render_placeholders "$stage" "$owner" "$name" "$pkg" "$desc"

# Files on the repo's exclude list (.github/repo-standard-exclude) are never
# copied or parked, so a re-run does not bring back what the repo dropped.
if [ -f "$target/$EXCLUDE_FILE" ]; then
  (cd "$stage" && find . -type f | sed 's#^\./##') | while read -r rel; do
    if excluded "$target" "$rel"; then rm -f "$stage/$rel"; echo "note: $rel skipped (on the repo's exclude list)"; fi
  done
fi

# put_fragment FILE MARKER FRAGMENT MODE: merge a fragment into FILE when FILE
# still carries the template MARKER (or in default mode), else park it for a
# hand merge. MODE is "replace" or "append".
put_fragment() {
  local file="$1" marker="$2" frag="$3" mode="$4"
  [ -f "$frag" ] && [ -s "$frag" ] || return 0
  # Re-runs: a marker with content after it was merged before (by this script
  # or by hand), so appending again would duplicate it.
  if [ "$retrofit" = 1 ] && [ "$mode" = append ] && [ -f "$file" ] &&
      awk -v m="$marker" 'index($0, m) { seen = 1; next } seen && NF { found = 1 } END { exit !found }' "$file"; then
    echo "note: ${file#"$target"/} already has the overlay's section; not appended again"
    return 0
  fi
  if [ "$retrofit" = 0 ] || { [ -f "$file" ] && grep -q "$marker" "$file"; }; then
    if [ "$mode" = replace ]; then cp "$frag" "$file"; else cat "$frag" >> "$file"; fi
  else
    mkdir -p "$merge_dir"
    cp "$frag" "$merge_dir/$(basename "$frag" | sed 's/^_//')"
    echo "note: merge $merge_dir/$(basename "$frag" | sed 's/^_//') into ${file#"$target"/} by hand"
  fi
}

if [ "$retrofit" = 1 ]; then
  info "retrofit: copying missing files only (overlay $overlay)"
  # Existing files are never overwritten. Where the standard's version
  # differs, park it next to the overlay fragments for a hand merge, so no
  # part of the standard is dropped silently. .gitignore lines merge safely.
  (cd "$stage" && find . -type f ! -path './src/*' ! -path './tests/*' ! -path './Sources/*' \
      ! -path './Tests/*' ! -path './cmd/*' ! -path './internal/*' ! -path './R/*' ! -path './api/*') |
    while read -r rel; do
      rel="${rel#./}"
      [ -f "$target/$rel" ] || continue
      cmp -s "$stage/$rel" "$target/$rel" && continue
      if [ "$rel" = .gitignore ]; then
        merge_gitignore "$stage/.gitignore" "$target/.gitignore" "$target"
        continue
      fi
      mkdir -p "$target/.scratch/repo-standard-merge/standard/$(dirname "$rel")"
      cp "$stage/$rel" "$target/.scratch/repo-standard-merge/standard/$rel"
      echo "note: $rel exists; the standard's version is in .scratch/repo-standard-merge/standard/$rel"
    done
  # Sample source and tests are for new repos; an existing repo has its own.
  copy_tree "$stage" "$target" --ignore-existing \
    --exclude '/src/' --exclude '/tests/' --exclude '/Sources/' --exclude '/Tests/' \
    --exclude '/cmd/' --exclude '/internal/' --exclude '/R/' --exclude '/api/'
else
  info "copying overlay $overlay"
  copy_tree "$stage" "$target"
fi

put_fragment "$target/.github/workflows/ci.yml" "Language overlays replace this file" "$src/_ci.yml" replace
put_fragment "$target/.pre-commit-config.yaml" "# LANGUAGE HOOKS (added by overlay)" "$src/_precommit.yaml" append
put_fragment "$target/.github/dependabot.yml" "# LANGUAGE ECOSYSTEMS (added by overlay)" "$src/_dependabot.yml" append
put_fragment "$target/AGENTS.md" "<!-- LANGUAGE COMMANDS (added by overlay) -->" "$src/_agents.md" append
if [ -s "$src/_gitignore" ]; then
  if [ "$retrofit" = 1 ]; then
    merge_gitignore "$src/_gitignore" "$target/.gitignore" "$target"
  else
    # New repos: keep the overlay's section comments for readability.
    while IFS= read -r line || [ -n "$line" ]; do
      grep -qxF -- "$line" "$target/.gitignore" || echo "$line" >> "$target/.gitignore"
    done < "$src/_gitignore"
  fi
fi

if [ -f "$src/_release-type" ]; then
  cfg="$target/release-please-config.json"
  if grep -q '"\.": {}' "$cfg" 2>/dev/null; then
    rtype="$(cat "$src/_release-type")"
    RT="$rtype" PN="$name" perl -0pi -e 's/"release-type": "[^"]*"/"release-type": "$ENV{RT}"/; s/"\.": \{\}/"." : { "package-name": "$ENV{PN}" }/' "$cfg"
    if [ "$overlay" = python ]; then
      # release-please bumps pyproject.toml but not uv.lock; without this every
      # release PR fails `uv sync --locked`. uv normalizes the name.
      uvname="$(echo "$name" | tr '[:upper:]_.' '[:lower:]--')"
      UV="$uvname" perl -0pi -e 's/"\." : \{ "package-name": "([^"]*)" \}/"." : {\n      "package-name": "$1",\n      "extra-files": [\n        { "type": "toml", "path": "uv.lock", "jsonpath": "\$.package[?(\@.name.value==\x27$ENV{UV}\x27)].version" }\n      ]\n    }/' "$cfg"
    fi
  else
    echo "note: $cfg already configured; set release-type $(cat "$src/_release-type") by hand if needed"
  fi
fi

# Default mode: the base template files in TARGET_DIR still hold placeholders.
[ "$retrofit" = 0 ] && render_placeholders "$target" "$owner" "$name" "$pkg" "$desc"
# Accounts other than the source owner keep their standard private: no links.
is_source_owner "$owner" || delink_standard "$target"

if [ "$retrofit" = 1 ]; then
  # Tracked symlinks usually point at a path on the author's machine and
  # break in CI (a fixture symlink failed 30 tests in the pilot).
  git -C "$target" ls-files -s 2>/dev/null | awk '$1 == "120000" { sub(/^[^\t]*\t/, ""); print }' |
    while read -r link; do
      echo "warning: $link is a tracked symlink to $(readlink "$target/$link"); CI cannot follow it. Commit the real file or remove it." >&2
    done || true  # a target that is not a git repo has no tracked links

  # dependency-review fails on the adoption PR unless the dependency graph is
  # on, so turn on Dependabot alerts now rather than after the merge.
  slug="$(origin_slug "$target")"
  if [ -n "$slug" ]; then
    # Subshell: gh_as exits through die when the owner has no gh login.
    if (gh_as "$owner" api -X PUT "repos/$slug/vulnerability-alerts" --silent) 2>/dev/null; then
      info "Dependabot alerts on for $slug (dependency-review needs them)"
    else
      echo "warning: could not turn on Dependabot alerts for $slug; dependency-review will fail until they are on" >&2
    fi
  else
    echo "note: no GitHub origin remote; turn on Dependabot alerts before opening the PR" >&2
  fi
fi
# Stamp the repository with the standard version it now follows (ADR 0002),
# its language overlay and its add-ons. Re-runs update the fields in place
# and keep any other line. Only the version is recorded, never a link to the
# source, so the stamp suits accounts that must stay unlinked.
stamp="$target/$STAMP_FILE"
std_version="$(manifest_version "$STANDARD_ROOT")"
[ -n "$std_version" ] || die "cannot read the standard's version from $STANDARD_ROOT/.release-please-manifest.json"
st_version="$(stamp_field "$stamp" standard-version)"
st_overlay="$(stamp_field "$stamp" overlay)"
st_addons="$(stamp_field "$stamp" addons | sed -E 's/^\[//; s/\]$//')"
st_vis="$(stamp_field "$stamp" visibility)"
# A repository that already records a version keeps it: adding an overlay
# does not bring the files it already has up to date. A first stamp records
# the current version, because a retrofit ends with the hand merge of every
# parked file (STANDARD.md section 13).
if [ -n "$st_version" ] && [ "$st_version" != "$std_version" ]; then
  echo "note: $stamp keeps standard-version $st_version; the version moves to $std_version when scripts/update-repo.sh updates the files"
  std_version="$st_version"
fi
if [ "$kind" = language ]; then
  case "$st_overlay" in ''|none|"$overlay") ;;
    *) echo "warning: the stamp recorded overlay $st_overlay; it now records $overlay (one language overlay per repository)" >&2 ;;
  esac
  st_overlay="$overlay"
fi
[ "$kind" = addon ] && case ", $st_addons," in *", $overlay,"*) ;; *) st_addons="${st_addons:+$st_addons, }$overlay" ;; esac
# --public sets the visibility; otherwise a recorded one is kept, and a
# language overlay applied without --public is a private repository.
if [ "$public" = 1 ]; then st_vis=public
elif [ -z "$st_vis" ] || [ "$st_vis" = unknown ]; then
  if [ "$kind" = language ]; then st_vis=private; else st_vis=unknown; fi
fi
mkdir -p "$target/.github"
[ -f "$stamp" ] || cat > "$stamp" <<'STAMP'
# Written by repo-standard (scripts/apply-overlay.sh): the version of the
# standard this repository follows, and what was applied from it. Updated by
# the scripts, not by hand.
STAMP
set_stamp_field "$stamp" standard-version "$std_version"
set_stamp_field "$stamp" overlay "${st_overlay:-none}"
set_stamp_field "$stamp" addons "[$st_addons]"
set_stamp_field "$stamp" visibility "$st_vis"
info "overlay $overlay applied to $target (standard $std_version)"
