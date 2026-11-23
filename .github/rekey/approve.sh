#!/usr/bin/env bash
# Opens a ReKey authentication for the person who asked to merge, waits for the
# phone's answer and reports it as the commit status `rekey/merge-approval`.
set -euo pipefail

: "${REKEY_URL:?}" "${REKEY_APPLICATION_ID:?}" "${REKEY_APPROVERS:?}" "${REKEY_API_KEY:?}"
: "${REPO:?}" "${PR:?}" "${TITLE:?}" "${BASE:?}" "${SHA:?}" "${ACTOR:?}" "${RUN_URL:?}"

CONTEXT_NAME=rekey/merge-approval
WAIT_SECONDS=300
REKEY_URL="${REKEY_URL%/}"

status() {
  gh api -X POST "repos/$REPO/statuses/$SHA" -f state="$1" -f context="$CONTEXT_NAME" \
    -f description="$2" -f target_url="$RUN_URL" >/dev/null
}

summary() {
  echo "$1" >>"$GITHUB_STEP_SUMMARY"
}

fail() {
  status failure "$1"
  summary "❌ $1"
  echo "::error::$1"
  exit 1
}

rekey() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" -w $'\n%{http_code}' -H "Authorization: Bearer $REKEY_API_KEY")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' --data "$body")
  curl "${args[@]}" "$REKEY_URL$path"
}

approver=$(jq -c --arg login "$ACTOR" '.[$login] // empty' <<<"$REKEY_APPROVERS")
[ -n "$approver" ] || fail "$ACTOR has no ReKey device in REKEY_APPROVERS"
user_id=$(jq -r '.user_id' <<<"$approver")
device_did=$(jq -r '.device_did' <<<"$approver")

# The context is hashed into the session and signed by the phone's transaction
# key, so the approval covers exactly this pull request and commit.
context=$(jq -nc --arg repo "$REPO" --argjson pr "$PR" --arg title "$TITLE" --arg base "$BASE" \
  --arg sha "$SHA" --arg by "$ACTOR" \
  '{type: "merge", repository: $repo, pull_request: $pr, title: $title, base: $base, head_sha: $sha, requested_by: $by}')
body=$(jq -nc --arg user "$user_id" --arg did "$device_did" --arg app "$REKEY_APPLICATION_ID" \
  --arg flow "${REKEY_FLOW_ID:-}" --arg message "Merge PR #$PR into $BASE" --argjson context "$context" \
  '{user_id: $user, device_did: $did, application_id: $app, context: $context, signed_message: $message}
   + (if $flow == "" then {} else {flow_id: $flow} end)')

response=$(rekey POST /api/authentications "$body")
code="${response##*$'\n'}"
payload="${response%$'\n'*}"
[ "$code" = 201 ] || fail "ReKey refused the request (HTTP $code: $(jq -r '.error // "unknown"' <<<"$payload" 2>/dev/null || echo unknown))"
request_id=$(jq -r '.request_id' <<<"$payload")

# A newer push cancels this run: withdraw its request so the phone shows only the newest one.
trap 'rekey DELETE "/api/authentications/$request_id" >/dev/null || true; exit 1' INT TERM

status pending "Waiting for $user_id to approve on the phone"
summary "⏳ Approval requested from **$user_id** (ReKey request \`$request_id\`). Open ReKey Authenticator on the phone."

deadline=$((SECONDS + WAIT_SECONDS))
while :; do
  sleep 3
  response=$(rekey GET "/api/authentications/$request_id")
  payload="${response%$'\n'*}"
  state=$(jq -r '.status // empty' <<<"$payload" 2>/dev/null || true)
  case "$state" in
    authenticated)
      status success "Approved on $user_id's phone"
      summary "✅ Approved on **$user_id**'s phone."
      summary "$(jq -r '"Checks: " + ([.policies[]? | select(.status != "not_evaluated") | "\(.policy) \(.status)"] | join(", "))' <<<"$payload")"
      exit 0
      ;;
    rejected | expired | cancelled)
      fail "Not approved on the phone ($state)"
      ;;
  esac
  if [ "$SECONDS" -ge "$deadline" ]; then
    rekey DELETE "/api/authentications/$request_id" >/dev/null || true
    fail "No approval within $((WAIT_SECONDS / 60)) minutes"
  fi
done
