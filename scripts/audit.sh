#!/usr/bin/env bash
# Usage: audit.sh [--as LOGIN] OWNER/REPO [LOCAL_DIR|-]
#        audit.sh [--as LOGIN] --all OWNER [PARENT]
# Reports how far a repository is from STANDARD.md: PASS, FAIL or N/A per
# rule. Every rule has a stable ID; docs/reference/audit-rules.md maps each
# ID to the OpenSSF OSPS Baseline control it covers. Read-only.
#   LOCAL_DIR  a local clone for the file checks (default: current dir;
#              "-" skips the file checks).
#   --as       read GitHub with LOGIN's token (default: the owner's). Checks
#              that need admin access are N/A when LOGIN is not an admin.
#   --all      one summary line per owned, non-archived source repository of
#              OWNER; file checks run where PARENT/OWNER/NAME is a clone
#              (default PARENT: ~/Projects). Exits 1 if any repository fails.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

as=""; all=""
while [ $# -gt 0 ]; do
  case "$1" in
    --as) as="${2:?--as needs a login}"; shift 2 ;;
    --all) all="${2:?--all needs an owner}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

if [ -n "$all" ]; then
  parent="${1:-$HOME/Projects}"; status=0
  names="$(gh_as "${as:-$all}" repo list "$all" --source --no-archived --limit 1000 \
    --json name,isEmpty --jq '.[] | select(.isEmpty | not) | .name' | sort)"
  [ -n "$names" ] || die "no non-empty source repositories found for $all"
  printf '%-55s %s\n' REPOSITORY RESULT
  for name in $names; do
    d="$parent/$all/$name"; note=""
    [ -d "$d/.git" ] || { d=-; note=" (settings only: no local clone)"; }
    rc=0; out="$("$0" ${as:+--as "$as"} "$all/$name" "$d" 2>&1)" || rc=$?
    [ "$rc" -eq 0 ] || status=1
    last="$(printf '%s\n' "$out" | tail -n 1)"
    case "$last" in result:*) ;; *) last="error: $last" ;; esac
    printf '%-55s %s%s\n' "$all/$name" "${last#result: }" "$note"
  done
  exit "$status"
fi

full="${1:?owner/repo}"; dir="${2:-$PWD}"; owner="${full%%/*}"
case "$full" in */*) ;; *) die "expected OWNER/REPO, got: $full" ;; esac
api() { gh_as "${as:-$owner}" "$@"; }
pass=0; fail=0; na=0
row() { printf '%-5s %-11s %s\n' "$1" "$2" "$3"; }
ok()  { row PASS "$1" "$2"; pass=$((pass + 1)); }
bad() { row FAIL "$1" "$2"; fail=$((fail + 1)); }
nap() { row N/A "$1" "$2"; na=$((na + 1)); }
# chk ID LABEL TEST: PASS when the shell TEST succeeds, else FAIL; N/A when
# the rule ID is on the repo's exclude list (.github/repo-standard-exclude).
chk() {
  if [ "$dir" != - ] && excluded "$dir" "$1"; then nap "$1" "$2 (excluded by the repo)"
  elif eval "$3"; then ok "$1" "$2"; else bad "$1" "$2"; fi
}
# xchk ID ENTRY LABEL TEST: N/A when ENTRY (path or hook:<id>) is on the
# repo's exclude list (.github/repo-standard-exclude), else a normal check.
xchk() { if excluded "$dir" "$2"; then nap "$1" "$3 (excluded by the repo)"; else chk "$1" "$3" "$4"; fi; }

repo_json="$(api api "repos/$full")"
j() { echo "$repo_json" | jq -r "$1"; }
private="$(j .private)"
admin="$(j .permissions.admin)"
no_license=0

if [ "$dir" = - ]; then
  echo "== files (skipped: no local clone)"
  nap "RS-FILE-*" "file, content, hook and CI checks need a local clone"
else
  [ -d "$dir" ] || die "no such folder: $dir"
  grep -qs 'No license: all rights reserved' "$dir/README.md" && no_license=1
  echo "== files ($dir)"
  # Each ID is fixed to its file. Append new files with the next free number;
  # never renumber or reuse an ID (docs/reference/audit-rules.md).
  while read -r id f; do
    xchk "RS-FILE-$id" "$f" "$f" "[ -f '$dir/$f' ]"
  done <<'FILES'
01 README.md
02 CONTRIBUTING.md
03 SECURITY.md
04 CODE_OF_CONDUCT.md
05 SUPPORT.md
06 AGENTS.md
07 .editorconfig
08 .gitignore
09 .pre-commit-config.yaml
10 release-please-config.json
11 .release-please-manifest.json
12 .github/pull_request_template.md
13 .github/dependabot.yml
14 .github/CODEOWNERS
15 .github/ISSUE_TEMPLATE/config.yml
16 .github/workflows/ci.yml
17 .github/workflows/pr-title.yml
18 .github/workflows/release-please.yml
19 .github/workflows/links.yml
20 .github/workflows/main-guard.yml
21 .claude/settings.json
22 .vale.ini
23 .lychee.toml
24 scripts/check_docs.py
25 docs/index.md
26 docs/dev/index.md
FILES
  if [ "$no_license" = 1 ]; then nap RS-LIC-01 "LICENSE (repo chose no license)"
  else xchk RS-LIC-01 LICENSE "LICENSE" "[ -f '$dir/LICENSE' ]"; fi

  echo "== content"
  chk RS-DOC-01 "README.md has a title and more than a stub" \
    "head -n 1 '$dir/README.md' 2>/dev/null | grep -q '^# ' && [ \"\$(grep -c . '$dir/README.md')\" -ge 10 ]"
  chk RS-DOC-02 "SECURITY.md names a private reporting route" \
    "grep -Eiqs 'report a vulnerability|security/advisories|mailto:|[[:alnum:]._-]+@[[:alnum:].-]+|privately' '$dir/SECURITY.md'"
  chk RS-DOC-03 "CONTRIBUTING.md describes the pull request process" "grep -iqs 'pull request' '$dir/CONTRIBUTING.md'"
  chk RS-DOC-04 ".scratch/ is gitignored" "grep -qsx '.scratch/' '$dir/.gitignore'"
  stray="$(cd "$dir" && git ls-files 2>/dev/null | RE="$SCRATCH_NAME_RE" EX="$SCRATCH_EXEMPT_RE" python3 -c '
import os, re, sys
name = re.compile(os.environ["RE"], re.I); exempt = re.compile(os.environ["EX"], re.I)
print(" ".join(p for p in sys.stdin.read().split() if name.search(p) and not exempt.search(p)))' || true)"
  chk RS-DOC-05 "no committed plan or notes files${stray:+ (found: $stray)}" "[ -z \"\$stray\" ]"

  echo "== hooks"
  unfrozen="$(grep -E '^\s+rev: ' "$dir/.pre-commit-config.yaml" 2>/dev/null | grep -vE 'rev: [0-9a-f]{40}' || true)"
  chk RS-HOOK-01 "pre-commit hook revs frozen to SHAs${unfrozen:+ (not frozen: $(echo "$unfrozen" | wc -l | tr -d ' ') revs)}" "[ -z \"\$unfrozen\" ]"
  for spec in 02:vale 03:lychee 04:check-docs 05:no-scratch-files 06:no-ai-attribution; do
    h="${spec#*:}"
    xchk "RS-HOOK-${spec%%:*}" "hook:$h" "hook configured: $h" "grep -qs 'id: $h\$' '$dir/.pre-commit-config.yaml'"
  done
  xchk RS-HOOK-07 .vale/ "Vale Google style vendored" "[ -f '$dir/.vale/styles/Google/Headings.yml' ]"
  chk RS-HOOK-08 "commit-msg hook installed locally (pre-commit install)" "[ -f '$dir/.git/hooks/commit-msg' ]"
  # The pre-push guard comes from the machine's git template (setup-machine.sh);
  # pre-commit keeps an existing hook as pre-push.legacy when it installs its own.
  chk RS-HOOK-09 "pre-push guard installed locally (scripts/setup-machine.sh, then git init)" \
    "grep -qs 'refusing to push to main' '$dir/.git/hooks/pre-push' '$dir/.git/hooks/pre-push.legacy'"

  echo "== workflows"
  wf="$dir/.github/workflows"
  chk RS-CI-01 "ci.yml has aggregate job 'ci' and a 'secrets' job" "grep -qs '^  ci:' '$wf/ci.yml' && grep -qs '^  secrets:' '$wf/ci.yml'"
  unpinned="$(grep -rhoE 'uses: [^ ]+@[^ ]+' "$wf" 2>/dev/null | grep -vE '@[0-9a-f]{40}$' | grep -v 'uses: \./' || true)"
  chk RS-CI-02 "all actions pinned to full SHAs${unpinned:+ (unpinned: $(echo "$unpinned" | tr '\n' ' '))}" "[ -z \"\$unpinned\" ]"
  chk RS-CI-03 "workflows set top-level permissions" "! grep -L '^permissions:' '$wf'/*.yml 2>/dev/null | grep -q ."
  chk RS-CI-04 "no pull_request_target" "! grep -rqs 'pull_request_target' '$wf'"
  # Untrusted event text inside an expression is only safe as an env value
  # (KEY: \${{ ... }}); inline in a script it is a code injection.
  inline="$(grep -rnE '\$\{\{[^}]*(github\.head_ref|github\.event\.(pull_request|issue|comment|review|review_comment|discussion|head_commit|commits|pages)[^}]*(title|body|ref|label|message|name|email|page_name))' "$wf" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:\s*[A-Za-z_][A-Za-z0-9_]*:\s*"?\$\{\{' | cut -d: -f1,2 | sed "s|$wf/||" | tr '\n' ' ' || true)"
  chk RS-CI-05 "untrusted event text reaches scripts only through env${inline:+ (inline: $inline)}" "[ -z \"\$inline\" ]"

  echo "== dependencies and releases"
  chk RS-DEP-01 "dependabot covers github-actions and pre-commit" \
    "grep -qs 'package-ecosystem: github-actions' '$dir/.github/dependabot.yml' && grep -qs 'package-ecosystem: pre-commit' '$dir/.github/dependabot.yml'"
  overlay="$(sed -n 's/^overlay: //p' "$dir/.github/repo-standard.yml" 2>/dev/null || true)"
  if [ "$overlay" = docs ]; then
    nap RS-DEP-02 "dependency manifest (docs overlay has none)"
  else
    chk RS-DEP-02 "dependency manifest present (pyproject.toml, package.json, go.mod, DESCRIPTION, Package.swift)" \
      "(for m in pyproject.toml package.json go.mod DESCRIPTION Package.swift; do [ -f '$dir/'\$m ] && exit 0; done; exit 1)"
  fi
  binaries="$(cd "$dir" && git ls-files 2>/dev/null \
    | grep -iE '\.(exe|dll|so|dylib|a|o|obj|lib|jar|war|class|pyc|pyo|whl|egg|msi|dmg|apk|ipa|bin)$' | head -n 5 | tr '\n' ' ' || true)"
  chk RS-DEP-03 "no committed binaries or build output${binaries:+ (found: $binaries)}" "[ -z \"\$binaries\" ]"
  chk RS-REL-01 "release-please tags are plain vX.Y.Z" "grep -qs '\"include-component-in-tag\": false' '$dir/release-please-config.json'"
  # The stamp written by apply-overlay.sh (ADR 0002): which version this repo follows.
  std_version="$(sed -nE 's/^[[:space:]]*"\.": "([^"]+)".*/\1/p' "$STANDARD_ROOT/.release-please-manifest.json")"
  repo_version="$(sed -nE 's/^standard-version: *([^ #]+).*/\1/p' "$dir/.github/repo-standard.yml" 2>/dev/null || true)"
  chk RS-REL-02 "stamped with a standard version (.github/repo-standard.yml${repo_version:+: $repo_version})" "[ -n \"\$repo_version\" ]"
  if [ -n "$repo_version" ]; then
    chk RS-REL-03 "follows the current standard ($std_version)" "[ \"\$repo_version\" = \"\$std_version\" ]"
  else
    nap RS-REL-03 "follows the current standard (no stamp)"
  fi
fi

echo "== settings ($full, $( [ "$private" = true ] && echo private || echo public ), read as ${as:-$owner}$( [ "$admin" = true ] || echo ', not admin'))"
spdx="$(j '.license.spdx_id // ""')"
if [ "$no_license" = 1 ]; then nap RS-LIC-02 "GitHub recognizes the license (repo chose no license)"
else chk RS-LIC-02 "GitHub recognizes the license${spdx:+ ($spdx)}" "[ -n \"\$spdx\" ] && [ \"\$spdx\" != NOASSERTION ]"; fi
if [ "$(j .allow_squash_merge)" = null ]; then
  nap "RS-SET-01" "merge settings (need push access to read)"
else
  chk RS-SET-01 "squash merge only" "[ \"$(j .allow_squash_merge)/$(j .allow_merge_commit)/$(j .allow_rebase_merge)\" = true/false/false ]"
  chk RS-SET-02 "squash title = PR title" "[ \"$(j .squash_merge_commit_title)\" = PR_TITLE ]"
  chk RS-SET-03 "squash message = PR body" "[ \"$(j .squash_merge_commit_message)\" = PR_BODY ]"
  chk RS-SET-04 "delete branch on merge" "[ \"$(j .delete_branch_on_merge)\" = true ]"
fi
default_branch="$(j .default_branch)"
hint=""; [ "$default_branch" = main ] || hint=" (now: $default_branch; rename, with the owner's OK: gh api -X POST repos/$full/branches/$default_branch/rename -f new_name=main)"
chk RS-SET-05 "default branch is main$hint" "[ \"$default_branch\" = main ]"
if [ "$private" = true ]; then
  nap RS-SET-06 "ruleset 'main' (rulesets need a public repo on the Free plan; RS-HOOK-09 and main-guard.yml cover it)"
  nap RS-SET-10 "secret scanning push protection (paid feature on private repos; gitleaks in CI covers it)"
  nap RS-SET-11 "public overlay (CodeQL, Scorecard)"
else
  rs_id="$(api api "repos/$full/rulesets" --jq '.[] | select(.name=="main") | .id' 2>/dev/null || true)"
  if [ -n "$rs_id" ]; then
    rs="$(api api "repos/$full/rulesets/$rs_id")"
    chk RS-SET-06 "ruleset 'main' active" "[ \"$(echo "$rs" | jq -r .enforcement)\" = active ]"
    chk RS-SET-07 "ruleset requires ci and pr-title" "[ \"$(echo "$rs" | jq -r '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | sort | join(",")')\" = ci,pr-title ]"
    chk RS-SET-08 "ruleset blocks deleting main and requires a pull request" \
      "[ \"$(echo "$rs" | jq -r '[.rules[].type | select(. == "deletion" or . == "pull_request")] | sort | join(",")')\" = deletion,pull_request ]"
    if [ "$admin" = true ]; then
      chk RS-SET-09 "ruleset has no bypass actors" "[ \"$(echo "$rs" | jq '.bypass_actors | length')\" = 0 ]"
    else
      nap RS-SET-09 "ruleset has no bypass actors (needs admin to read)"
    fi
  else
    bad RS-SET-06 "ruleset 'main' exists"
  fi
  if [ "$admin" = true ]; then
    chk RS-SET-10 "secret scanning push protection" "[ \"$(j '.security_and_analysis.secret_scanning_push_protection.status')\" = enabled ]"
  else
    nap RS-SET-10 "secret scanning push protection (needs admin to read)"
  fi
  if [ "$dir" = - ]; then
    nap RS-SET-11 "public overlay files (no local clone)"
  else
    xchk RS-SET-11 .github/workflows/codeql.yml "public overlay: codeql.yml" "[ -f '$dir/.github/workflows/codeql.yml' ]"
    xchk RS-SET-12 .github/workflows/scorecard.yml "public overlay: scorecard.yml" "[ -f '$dir/.github/workflows/scorecard.yml' ]"
  fi
fi
if [ "$admin" = true ]; then
  chk RS-SET-13 "Dependabot alerts enabled" "api api 'repos/$full/vulnerability-alerts' --silent 2>/dev/null"
else
  nap RS-SET-13 "Dependabot alerts enabled (needs admin to read)"
fi
chk RS-REL-04 "release App client id variable set" "api variable list --repo '$full' 2>/dev/null | grep -q RELEASE_APP_CLIENT_ID"

echo; echo "result: $pass passed, $fail failed, $na not applicable"
[ "$fail" -eq 0 ]
