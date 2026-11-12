#!/usr/bin/env bash
# Usage: apply-settings.sh OWNER/REPO public|private
# Applies the repository settings from STANDARD.md. Safe to re-run.
#   - merge options: squash only, PR title and body, delete merged branches
#   - Actions: read-only default token, Actions may not approve PRs
#   - security: Dependabot alerts and fixes, private vulnerability reporting,
#     secret scanning with push protection (public)
#   - labels
#   - the "main" ruleset (PR required, ci + pr-title checks bound to the
#     GitHub Actions app, linear history, resolved conversations, no force
#     push or deletion, no bypass) and a "release-tags" ruleset for v* tags
#   - Actions must be pinned to full commit SHAs
#   - repo variable RELEASE_APP_CLIENT_ID, read from the owner's private
#     config (see scripts/lib.sh); release-please skips until the secret exists
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

full="${1:?owner/repo}"; vis="${2:?public|private}"
owner="${full%%/*}"
gh_() { gh_as "$owner" "$@"; }
warn() { echo "warning: $*" >&2; WARNINGS+=("$*"); }
WARNINGS=()

info "merge options"
gh_ api -X PATCH "repos/$full" --silent \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true -F allow_update_branch=true -F allow_auto_merge=false

info "Actions: allowed, actions must be pinned to full SHAs"
gh_ api -X PUT "repos/$full/actions/permissions" --silent \
  -F enabled=true -f allowed_actions=all -F sha_pinning_required=true ||
  warn "could not require SHA-pinned actions"

info "Actions token permissions"
gh_ api -X PUT "repos/$full/actions/permissions/workflow" --silent \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false

info "security features"
gh_ api -X PUT "repos/$full/vulnerability-alerts" --silent || warn "Dependabot alerts not enabled"
gh_ api -X PUT "repos/$full/automated-security-fixes" --silent || warn "Dependabot security updates not enabled"
if [ "$vis" = public ]; then
  gh_ api -X PUT "repos/$full/private-vulnerability-reporting" --silent || warn "private vulnerability reporting not enabled"
fi
if [ "$vis" = public ]; then
  gh_ api -X PATCH "repos/$full" --silent --input - <<'JSON' || warn "secret scanning not enabled"
{"security_and_analysis": {"secret_scanning": {"status": "enabled"}, "secret_scanning_push_protection": {"status": "enabled"}}}
JSON
fi

info "labels"
while IFS='|' read -r lname color ldesc; do
  gh_ label create "$lname" --repo "$full" --color "$color" --description "$ldesc" --force >/dev/null
done <<'LABELS'
type/bug|d73a4a|Something does not work as documented
type/feature|a2eeef|New capability or behavior change
type/docs|0075ca|Documentation only
type/chore|cfd3d7|Maintenance, tooling, dependencies
priority/high|b60205|Needed soon
priority/medium|fbca04|Normal priority
priority/low|c5def5|Nice to have
status/needs-triage|ededed|Not reviewed yet
status/blocked|000000|Waiting on something else
good first issue|7057ff|Small, well-defined starter task
dependencies|0366d6|Dependency updates
LABELS

load_owner "$owner"
if [ -n "${RELEASE_APP_CLIENT_ID:-}" ]; then
  info "release App client id variable"
  gh_ variable set RELEASE_APP_CLIENT_ID --repo "$full" --body "$RELEASE_APP_CLIENT_ID"
else
  warn "RELEASE_APP_CLIENT_ID unknown; put it in $CONFIG_DIR/$owner.env"
fi

info "main ruleset"
ruleset='{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_linear_history"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true,
      "allowed_merge_methods": ["squash"]}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "do_not_enforce_on_create": false,
      "required_status_checks": [
        {"context": "ci", "integration_id": 15368},
        {"context": "pr-title", "integration_id": 15368}]}}
  ]
}'
# Rulesets need a public repo on the Free plan (GitHub answers 403 otherwise).
if ! rulesets_json="$(gh_ api "repos/$full/rulesets" 2>/dev/null)"; then
  info "rulesets unavailable for this repo (private on the Free plan); CI, hooks and process rules are the gate"
  rulesets_json=""
fi
existing="$(printf '%s' "$rulesets_json" | jq -r '.[]? | select(.name=="main") | .id')"
if [ -z "$rulesets_json" ]; then
  :
elif [ -n "$existing" ]; then
  echo "$ruleset" | gh_ api -X PUT "repos/$full/rulesets/$existing" --input - --silent ||
    warn "ruleset update failed"
else
  echo "$ruleset" | gh_ api -X POST "repos/$full/rulesets" --input - --silent ||
    warn "ruleset not created (private repos on the Free plan may not support rulesets); CI, hooks and process rules still apply"
fi

info "release tag ruleset (v* tags cannot be moved or deleted)"
tag_ruleset='{
  "name": "release-tags",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
  "rules": [{"type": "deletion"}, {"type": "non_fast_forward"}, {"type": "update"}]
}'
tag_id="$(printf '%s' "$rulesets_json" | jq -r '.[]? | select(.name=="release-tags") | .id')"
if [ -z "$rulesets_json" ]; then
  :
elif [ -n "$tag_id" ]; then
  echo "$tag_ruleset" | gh_ api -X PUT "repos/$full/rulesets/$tag_id" --input - --silent || warn "tag ruleset update failed"
else
  echo "$tag_ruleset" | gh_ api -X POST "repos/$full/rulesets" --input - --silent || warn "tag ruleset not created"
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo; echo "Finished with warnings:"; printf '  - %s\n' "${WARNINGS[@]}"
else
  info "all settings applied to $full"
fi
