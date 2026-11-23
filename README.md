# test-otp — ReKey merge approval demo

Merging into `main` needs an approval on the phone. The check `rekey/merge-approval`
is required by a ruleset on `main`:

1. Open a pull request. The check is pending: "Add the label rekey-approve…".
2. Add the label **`rekey-approve`**. The workflow opens a ReKey authentication for
   you on the deployed ReKey, with the pull request, its target branch and head commit
   as the operation context.
3. Open **ReKey Authenticator** on your phone: the request shows "Approve merge",
   the repository, PR, branch and commit. Approve with Face ID and your PIN. The
   phone signs the request with the key it enrolled when it was linked.
4. The check turns green and the pull request can be merged. A rejection or no answer
   within 5 minutes turns it red. A new commit resets the check and drops the label.

## Setup

- Secret `REKEY_API_KEY`: a server-channel API key of the ReKey project.
- Variables: `REKEY_URL`, `REKEY_APPLICATION_ID`, `REKEY_FLOW_ID` (optional) and
  `REKEY_APPROVERS`, a JSON map from GitHub login to the ReKey user and device:
  `{"octocat": {"user_id": "…", "device_did": "did:jwk:…"}}`.
- The workflow: [`.github/workflows/rekey-merge-approval.yml`](.github/workflows/rekey-merge-approval.yml),
  the script: [`.github/rekey/approve.sh`](.github/rekey/approve.sh).
