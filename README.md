# test-otp — ReKey merge approval demo

Merging into `main` needs an approval on the phone. The check `rekey/merge-approval`
is required by a ruleset on `main`:

1. Open a pull request, or push a new commit to one. The workflow asks rekey-backend,
   which opens a ReKey authentication for you with the pull request, its target branch
   and head commit as the operation context.
2. Open **ReKey Authenticator** on your phone: the request shows "Approve merge",
   the repository, PR, branch and commit. Approve with Face ID and your PIN. The
   phone signs the request with the key it enrolled when it was linked.
3. The check turns green and the pull request can be merged. A rejection or no answer
   within 5 minutes turns it red; "Re-run jobs" on the check asks again. Every new
   commit needs its own approval, and a newer push withdraws a request still waiting.

## Setup

- rekey-backend (the relying party) holds the ReKey API key, the linked phones and the flow:
  - **GitHub page**: link each person's phone (enter the GitHub login, scan the QR with
    ReKey Authenticator) and create an integration token for this repo.
  - **Rules page**: pick the merge approval flow.
- In this repo: variable `REKEY_BACKEND_URL` (the backend's base URL) and secret
  `REKEY_BACKEND_TOKEN` (the integration token).
- The workflow: [`.github/workflows/rekey-merge-approval.yml`](.github/workflows/rekey-merge-approval.yml),
  the script: [`.github/rekey/approve.sh`](.github/rekey/approve.sh).
