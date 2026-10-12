# Branching, commits and pull requests

**Goal:** every change to the Mule apps is reviewed and traceable; nothing is deployed that is not on `main`.

## Branches
- `main` — the only long-lived branch; always releasable; **no direct commits** (by team rule; enforce with branch protection when the GitHub plan allows it).
- `feature/<ticket-or-topic>` — one topic per branch, short-lived (`feature/jira-duplicate-check`, `fix/err-0023-webhook-hmac`).
- No environment branches and no environment repositories: Dev, UAT, Preprod and Production all run commits of `main`. Each deployment is recorded by an annotated tag `<env>/<yyyy-mm-dd>` on the commit the JARs were built from (`uat/2026-10-14`; a second deployment the same day `uat/2026-10-14-2`). The full procedure, the per-environment files and the deployment log: `docs/DEPLOY.md`.

## Commits
`<app>: <imperative summary>` — e.g. `provisioning-prc-api: park transient failures for 14 days`. Repo-wide changes use `repo:` / `docs:` / `demo:` / `tools:`. One logical change per commit; never commit `target/`, keystores, `.env` files or plain secrets (the `.gitignore` guards the common shapes — still look at `git status` before every commit).

## Pull requests
1. Push the branch, open a PR against `main`, fill in the template.
2. Required before review: `mvn clean test` green in every app touched; the KB updated if a decision, error or runbook step changed.
3. One approving review from another Bluvium developer; the author does not merge their own PR without it.
4. **Squash-merge**; delete the branch.
5. Deployments happen only from a commit on `main`, announced in the team channel before and after, one environment at a time; the three apps of an environment are built from the same commit, and that commit gets the environment's tag (`docs/DEPLOY.md` §7).

## What never goes into the repository
The AES key (`MULE_SECURE_KEY`), the inter-app secret in plain form, keystores (`*.jks`, `*.p12`, `*.key`), Anypoint connected-app secrets, Salesforce or Jira tokens, `~/.m2/settings.xml`, and anything the client marks confidential. Encrypted `secure-<env>.yaml` values are fine.
