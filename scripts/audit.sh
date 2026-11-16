#!/usr/bin/env bash
# Usage: audit.sh OWNER/REPO [LOCAL_DIR]
# Reports how far a repository is from STANDARD.md: PASS, FAIL or N/A per rule.
# Read-only. File checks need a local clone (LOCAL_DIR, default: current dir).
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

full="${1:?owner/repo}"; dir="${2:-$PWD}"; owner="${full%%/*}"
pass=0; fail=0; na=0
ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
nap() { printf 'N/A   %s\n' "$1"; na=$((na + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# xchk ENTRY LABEL TEST: N/A when ENTRY (path or hook:<id>) is on the repo's
# exclude list (.github/repo-standard-exclude), else a normal check.
xchk() { if excluded "$dir" "$1"; then nap "$2 (excluded by the repo)"; else chk "$2" "$3"; fi; }

repo_json="$(gh_as "$owner" api "repos/$full")"
j() { echo "$repo_json" | jq -r "$1"; }
private="$(j .private)"
no_license=0; grep -q 'No license: all rights reserved' "$dir/README.md" 2>/dev/null && no_license=1

echo "== files ($dir)"
for f in README.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md AGENTS.md \
  .editorconfig .gitignore .pre-commit-config.yaml release-please-config.json \
  .release-please-manifest.json .github/pull_request_template.md .github/dependabot.yml \
  .github/CODEOWNERS .github/ISSUE_TEMPLATE/config.yml \
  .github/workflows/ci.yml .github/workflows/pr-title.yml .github/workflows/release-please.yml \
  .github/workflows/links.yml .github/workflows/main-guard.yml .vale.ini .lychee.toml scripts/check_docs.py docs/index.md docs/dev/index.md; do
  xchk "$f" "$f" "[ -f '$dir/$f' ]"
done
if [ "$no_license" = 1 ]; then nap "LICENSE (repo chose no license)"; else xchk LICENSE "LICENSE" "[ -f '$dir/LICENSE' ]"; fi
chk "ci.yml has aggregate job 'ci' and a 'secrets' job" "grep -q '^  ci:' '$dir/.github/workflows/ci.yml' 2>/dev/null && grep -q '^  secrets:' '$dir/.github/workflows/ci.yml'"
chk "dependabot covers github-actions and pre-commit" "grep -q 'package-ecosystem: github-actions' '$dir/.github/dependabot.yml' 2>/dev/null && grep -q 'package-ecosystem: pre-commit' '$dir/.github/dependabot.yml'"
chk "release-please tags are plain vX.Y.Z" "grep -q '\"include-component-in-tag\": false' '$dir/release-please-config.json' 2>/dev/null"
unpinned="$(grep -rhoE 'uses: [^ ]+@[^ ]+' "$dir/.github/workflows" 2>/dev/null | grep -vE '@[0-9a-f]{40}$' | grep -v 'uses: \./' || true)"
chk "all actions pinned to full SHAs${unpinned:+ (unpinned: $(echo "$unpinned" | tr '\n' ' '))}" "[ -z \"\$unpinned\" ]"
unfrozen="$(grep -E '^\s+rev: ' "$dir/.pre-commit-config.yaml" 2>/dev/null | grep -vE 'rev: [0-9a-f]{40}' || true)"
chk "pre-commit hook revs frozen to SHAs${unfrozen:+ (not frozen: $(echo "$unfrozen" | wc -l | tr -d ' ') revs)}" "[ -z \"\$unfrozen\" ]"
chk "workflows set top-level permissions" "! grep -L '^permissions:' '$dir'/.github/workflows/*.yml 2>/dev/null | grep -q ."
chk "no pull_request_target" "! grep -rq 'pull_request_target' '$dir/.github/workflows' 2>/dev/null"
xchk .vale/ "Vale Google style vendored" "[ -f '$dir/.vale/styles/Google/Headings.yml' ]"
chk ".scratch/ is gitignored" "grep -qx '.scratch/' '$dir/.gitignore' 2>/dev/null"
for h in vale lychee check-docs no-scratch-files; do
  xchk "hook:$h" "docs hook configured: $h" "grep -q 'id: $h' '$dir/.pre-commit-config.yaml' 2>/dev/null"
done
stray="$(cd "$dir" && git ls-files 2>/dev/null | RE="$SCRATCH_NAME_RE" EX="$SCRATCH_EXEMPT_RE" python3 -c '
import os, re, sys
name = re.compile(os.environ["RE"], re.I); exempt = re.compile(os.environ["EX"], re.I)
print(" ".join(p for p in sys.stdin.read().split() if name.search(p) and not exempt.search(p)))' || true)"
chk "no committed plan or notes files${stray:+ (found: $stray)}" "[ -z \"\$stray\" ]"
chk "commit-msg hook installed locally" "[ -f '$dir/.git/hooks/commit-msg' ]"
# The pre-push guard comes from the machine's git template (setup-machine.sh);
# pre-commit keeps an existing hook as pre-push.legacy when it installs its own.
chk "pre-push guard installed locally (scripts/setup-machine.sh, then git init)" \
  "grep -qs 'refusing to push to main' '$dir/.git/hooks/pre-push' '$dir/.git/hooks/pre-push.legacy'"

echo "== settings ($full, $( [ "$private" = true ] && echo private || echo public ))"
chk "squash merge only" "[ \"$(j .allow_squash_merge)/$(j .allow_merge_commit)/$(j .allow_rebase_merge)\" = true/false/false ]"
chk "squash title = PR title" "[ \"$(j .squash_merge_commit_title)\" = PR_TITLE ]"
chk "squash message = PR body" "[ \"$(j .squash_merge_commit_message)\" = PR_BODY ]"
chk "delete branch on merge" "[ \"$(j .delete_branch_on_merge)\" = true ]"
default_branch="$(j .default_branch)"
hint=""; [ "$default_branch" = main ] || hint=" (now: $default_branch; rename, with the owner's OK: gh api -X POST repos/$full/branches/$default_branch/rename -f new_name=main)"
chk "default branch is main$hint" "[ \"$default_branch\" = main ]"
if [ "$private" = true ]; then
  nap "ruleset 'main' (rulesets need a public repo on the Free plan; CI, hooks and process rules apply)"
  nap "secret scanning push protection (paid feature on private repos; gitleaks in CI covers it)"
  nap "public overlay (CodeQL, Scorecard)"
else
  rs_id="$(gh_as "$owner" api "repos/$full/rulesets" --jq '.[] | select(.name=="main") | .id' 2>/dev/null || true)"
  if [ -n "$rs_id" ]; then
    rs="$(gh_as "$owner" api "repos/$full/rulesets/$rs_id")"
    chk "ruleset 'main' active" "[ \"$(echo "$rs" | jq -r .enforcement)\" = active ]"
    chk "ruleset requires ci and pr-title" "[ \"$(echo "$rs" | jq -r '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | sort | join(",")')\" = ci,pr-title ]"
    chk "ruleset has no bypass actors" "[ \"$(echo "$rs" | jq '.bypass_actors | length')\" = 0 ]"
  else
    bad "ruleset 'main' exists"
  fi
  chk "secret scanning push protection" "[ \"$(j '.security_and_analysis.secret_scanning_push_protection.status')\" = enabled ]"
  xchk .github/workflows/codeql.yml "public overlay: codeql.yml" "[ -f '$dir/.github/workflows/codeql.yml' ]"
  xchk .github/workflows/scorecard.yml "public overlay: scorecard.yml" "[ -f '$dir/.github/workflows/scorecard.yml' ]"
fi
chk "Dependabot alerts enabled" "gh_as '$owner' api 'repos/$full/vulnerability-alerts' --silent 2>/dev/null"
chk "release App client id variable set" "gh_as '$owner' variable list --repo '$full' 2>/dev/null | grep -q RELEASE_APP_CLIENT_ID"

echo; echo "result: $pass passed, $fail failed, $na not applicable"
[ "$fail" -eq 0 ]
