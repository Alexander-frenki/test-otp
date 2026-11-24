#!/usr/bin/env bash
# Asks rekey-backend to approve this merge on the pusher's phone, waits for the
# answer and reports it as the commit status `rekey/merge-approval`. The backend
# holds the ReKey API key, the linked phones and the flow; this repo only holds
# its URL and an integration token.
set -euo pipefail

: "${REKEY_BACKEND_URL:?}" "${REKEY_BACKEND_TOKEN:?}"
: "${REPO:?}" "${PR:?}" "${TITLE:?}" "${BASE:?}" "${SHA:?}" "${ACTOR:?}" "${RUN_URL:?}"

CONTEXT_NAME=rekey/merge-approval
WAIT_SECONDS=300
APPROVALS="${REKEY_BACKEND_URL%/}/api/github/merge-approvals"

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

backend() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" -w $'\n%{http_code}' -H "Authorization: Bearer $REKEY_BACKEND_TOKEN")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' --data "$body")
  curl "${args[@]}" "$APPROVALS$path"
}

body=$(jq -nc --arg repo "$REPO" --argjson pr "$PR" --arg title "$TITLE" --arg base "$BASE" \
  --arg sha "$SHA" --arg by "$ACTOR" \
  '{repository: $repo, pull_request: $pr, title: $title, base: $base, head_sha: $sha, requested_by: $by}')

response=$(backend POST "" "$body") || fail "rekey-backend is unreachable"
code="${response##*$'\n'}"
payload="${response%$'\n'*}"
error=$(jq -r '.error // "unknown"' <<<"$payload" 2>/dev/null || echo unknown)
case "$code" in
  201) ;;
  404) fail "$ACTOR has no linked phone: link it on rekey-backend's GitHub page" ;;
  503) fail "No merge approval flow is set on rekey-backend's Rules page ($error)" ;;
  *) fail "rekey-backend refused the request (HTTP $code: $error)" ;;
esac
request_id=$(jq -r '.request_id' <<<"$payload")

# A newer push cancels this run: withdraw its request so the phone shows only the newest one.
trap 'backend DELETE "/$request_id" >/dev/null || true; exit 1' INT TERM

status pending "Waiting for $ACTOR to approve on the phone"
summary "⏳ Approval requested from **$ACTOR**'s phone (ReKey request \`$request_id\`). Open ReKey Authenticator."

deadline=$((SECONDS + WAIT_SECONDS))
while :; do
  sleep 3
  response=$(backend GET "/$request_id") || continue
  payload="${response%$'\n'*}"
  state=$(jq -r '.status // empty' <<<"$payload" 2>/dev/null || true)
  case "$state" in
    authenticated)
      status success "Approved on $ACTOR's phone"
      summary "✅ Approved on **$ACTOR**'s phone."
      exit 0
      ;;
    rejected | expired | cancelled | not_found)
      fail "Not approved on the phone ($state)"
      ;;
  esac
  if [ "$SECONDS" -ge "$deadline" ]; then
    backend DELETE "/$request_id" >/dev/null || true
    fail "No approval within $((WAIT_SECONDS / 60)) minutes"
  fi
done
