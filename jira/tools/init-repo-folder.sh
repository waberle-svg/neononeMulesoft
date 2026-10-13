#!/bin/zsh
# Creates the clean, source-tracked repository folder for the Neon One Mule apps from the working folder.
# Copies only what belongs in Git (no target/, no IDE caches, no secrets), writes the scaffold files
# (README, .gitignore, workspace, PR template, CODEOWNERS, docs), and initialises git on branch main.
# It does NOT create the GitHub repository and does NOT push. Nothing in the source folder is modified.
#
# Usage:  zsh tools/init-repo-folder.sh [destination]      default destination: ~/Desktop/Mulesoft-N-One
set -e
# Historical: used once to create this repository from the pre-Git working folder. Kept for reference.
SRC="${SRC:-$(cd "$(dirname "$0")/.." && pwd)}"
DEST="${1:-$HOME/Desktop/Mulesoft-N-One}"
KB="${KB:-$HOME/Desktop/NEONONE-KB}"
REPO_NAME="$(basename "$DEST")"

if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "Destination $DEST exists and is not empty. Remove it or choose another path." >&2; exit 1
fi
mkdir -p "$DEST"

# 1) The three apps, demo scripts and tools — excluding build output, IDE caches and every secret shape
for APP in jira-sys-api salesforce-sys-api provisioning-prc-api; do
  rsync -a "$SRC/$APP/" "$DEST/$APP/" \
    --exclude 'target/' --exclude '.mule/' --exclude '.tooling-project/' --exclude 'services/' \
    --exclude '.DS_Store' --exclude '*.jks' --exclude '*.p12' --exclude '*.key' --exclude '*.env' \
    --exclude 'secure-*.plain.yaml' --exclude 'src/test/resources/embedded-dw_*'
done
rsync -a "$SRC/demo/" "$DEST/demo/" --exclude '.last-demo.env' --exclude '.DS_Store'
mkdir -p "$DEST/tools" "$DEST/docs" "$DEST/.github" "$DEST/.secrets/dev"
cp "$SRC/tools/secure-properties-tool.jar" "$DEST/tools/"
cp "$SRC/tools/bundle-sources-for-study.sh" "$DEST/tools/"
cp "$SRC/tools/init-repo-folder.sh" "$DEST/tools/"
# the MUnit dummy keystore is test data, not a secret — keep it (it is whitelisted in the app's .gitignore)
[ -f "$SRC/salesforce-sys-api/src/test/resources/keystore/munit-dummy.jks" ] && \
  mkdir -p "$DEST/salesforce-sys-api/src/test/resources/keystore" && \
  cp "$SRC/salesforce-sys-api/src/test/resources/keystore/munit-dummy.jks" "$DEST/salesforce-sys-api/src/test/resources/keystore/"

# 2) Docs from the knowledge base
cp "$KB/01-MULESOFT/16-teammate-setup-guide.md" "$DEST/docs/SETUP.md"

# 3) Scaffold files
cat > "$DEST/.gitignore" <<'EOF'
# Build output and IDE caches (per app)
**/target/
**/.mule/
**/.tooling-project/
**/services/
.DS_Store
*.log

# Secrets — never in Git. Encrypted secure-<env>.yaml files ARE committed; keys, keystores and env files are NOT.
.secrets/*
!.secrets/README.md
*.env
.env.*
**/secure-*.plain.yaml
*.key
*.p12
*.jks
!**/src/test/resources/keystore/munit-dummy.jks
demo/.last-demo.env

# Local editor state
.vscode/settings.json
*.code-workspace.bak
EOF

cat > "$DEST/.secrets/README.md" <<'EOF'
# .secrets/ (git-ignored)
Put the environment keystores here, from the team vault:
- `dev/neon-jira-integration-dev.jks` — master copy; also copy it to `salesforce-sys-api/src/main/resources/keystore/` so it is packaged.
Nothing else in this folder is ever committed (see the root `.gitignore`).
EOF

cat > "$DEST/.mule-local.env.example" <<'EOF'
# Copy to .mule-local.env (git-ignored) and fill from the team vault. Never commit the real file.
MULE_SECURE_KEY=<16-character AES key that decrypts config/secure-<env>.yaml>
INTER_APP_SECRET=<plain inter-app secret, used only for manual curl checks>
EOF

cat > "$DEST/$REPO_NAME.code-workspace" <<'EOF'
{
  "folders": [
    { "name": "salesforce-sys-api",   "path": "salesforce-sys-api" },
    { "name": "jira-sys-api",         "path": "jira-sys-api" },
    { "name": "provisioning-prc-api", "path": "provisioning-prc-api" },
    { "name": "repo root (docs, demo, tools)", "path": "." }
  ],
  "settings": {
    "files.exclude": {
      "**/.git": true, "**/.DS_Store": true, "**/.mule": true, "**/target": true,
      "**/.tooling-project": true, "**/services": true
    },
    "files.eol": "\n",
    "mule.runtime.defaultArguments": "-M-Dmule.env=dev -M-Dsecure.key=REPLACE_WITH_MULE_SECURE_KEY_FROM_.mule-local.env"
  }
}
EOF

cat > "$DEST/README.md" <<EOF
# $REPO_NAME — Neon One Salesforce ↔ Jira integration on MuleSoft

Three Mule 4 applications (API-led) that replace Neon One's Talend jobs:

| App | Layer | Port (local) | Owns |
|---|---|---|---|
| \`salesforce-sys-api\` | system | 8081 | Salesforce JWT connection, \`Integration_Request__e\` subscription, registry (\`Integration_Transaction__c\`) reads/writes |
| \`jira-sys-api\` | system | 8082 | Jira Cloud REST v3, field-id mapping, webhook receiver |
| \`provisioning-prc-api\` | process | 8083 | Business rules: idempotency, ticket mapping, retry, inbound status events, reconciliation sweep |

Runtime **Mule 4.12.3 / Java 17**, built with Maven, tested with MUnit, deployed to **CloudHub 2.0** (private space *Bluvium*, Anypoint org *Neon One*).

- New here? Read [docs/SETUP.md](docs/SETUP.md) first, then [docs/BRANCHING.md](docs/BRANCHING.md).
- Open the **workspace file** \`$REPO_NAME.code-workspace\` in VS Code, not the folder (the MuleSoft extension needs each app at a workspace root).
- Architecture, decisions, runbooks and the error log live in the Bluvium knowledge base \`NEONONE-KB\` (ask the integration team).
- Secrets: encrypted \`config/secure-<env>.yaml\` files are committed; the AES key, keystores and \`.mule-local.env\` are **never** committed — see \`docs/SETUP.md\` §4.

## Build
\`\`\`bash
for app in jira-sys-api salesforce-sys-api provisioning-prc-api; do (cd \$app && mvn -B clean test) || break; done
\`\`\`
EOF

cat > "$DEST/docs/BRANCHING.md" <<'EOF'
# Branching, commits and pull requests

**Goal:** every change to the Mule apps is reviewed and traceable; nothing is deployed that is not on `main`.

## Branches
- `main` — the only long-lived branch; always releasable; **no direct commits** (by team rule; enforce with branch protection when the GitHub plan allows it).
- `feature/<ticket-or-topic>` — one topic per branch, short-lived (`feature/jira-duplicate-check`, `fix/err-0023-webhook-hmac`).
- Releases: tag `main` as `v<major>.<minor>.<patch>` when a version is deployed to UAT/Production; the pom version follows.

## Commits
`<app>: <imperative summary>` — e.g. `provisioning-prc-api: park transient failures for 14 days`. Repo-wide changes use `repo:` / `docs:` / `demo:` / `tools:`. One logical change per commit; never commit `target/`, keystores, `.env` files or plain secrets (the `.gitignore` guards the common shapes — still look at `git status` before every commit).

## Pull requests
1. Push the branch, open a PR against `main`, fill in the template.
2. Required before review: `mvn clean test` green in every app touched; the KB updated if a decision, error or runbook step changed.
3. One approving review from another Bluvium developer; the author does not merge their own PR without it.
4. **Squash-merge**; delete the branch.
5. Deployments happen only from `main`, announced in the team channel before and after, one environment at a time.

## What never goes into the repository
The AES key (`MULE_SECURE_KEY`), the inter-app secret in plain form, keystores (`*.jks`, `*.p12`, `*.key`), Anypoint connected-app secrets, Salesforce or Jira tokens, `~/.m2/settings.xml`, and anything the client marks confidential. Encrypted `secure-<env>.yaml` values are fine.
EOF

cat > "$DEST/.github/PULL_REQUEST_TEMPLATE.md" <<'EOF'
## What and why
<!-- One paragraph: the behaviour change and the reason (ticket / KB reference). -->

## Apps touched
- [ ] jira-sys-api
- [ ] salesforce-sys-api
- [ ] provisioning-prc-api
- [ ] demo / tools / docs only

## Checklist
- [ ] `mvn clean test` green in every app touched (paste the `Tests run:` lines below)
- [ ] No secret values, keystores, `.env` files or `target/` in the diff
- [ ] Config changes mirrored in `config-dev.yaml`, `config-uat.yaml`, `config-prod.yaml` (and `config-test.yaml` if tests read it)
- [ ] RAML updated if an endpoint or model changed
- [ ] Knowledge base updated (ADR / ERR / runbook) if a decision, error or operating step changed

## Test evidence
```
```

## Deployment notes
<!-- New Runtime Manager properties? Order of deployment? Rollback? "None" is a valid answer. -->
EOF

cat > "$DEST/.github/CODEOWNERS" <<'EOF'
# Reviews requested automatically from these owners (enforced only with branch protection).
* @ayushbluvium
EOF

# 4) Git init on main, first commit
(
  cd "$DEST"
  git init -q -b main
  git add -A
  git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo developer)}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo ayush.upadhyaya@bluvium.com)}" \
      commit -q -m "repo: initial import of the three Neon One Mule apps, demo scripts, tools and docs" \
      -m "Imported from the working folder without build output, IDE caches or secrets. Encrypted secure-dev.yaml files are included; keys and keystores are not."
)

# 5) Safety report
echo "== Folder created: $DEST"
echo "== Files committed: $(cd "$DEST" && git ls-files | wc -l | tr -d ' ')"
echo "== Secret-shape check (must be empty):"
(cd "$DEST" && git ls-files | grep -E '\.jks$|\.p12$|\.key$|\.env$|/target/|\.secrets/dev/' | grep -v munit-dummy.jks || true)
echo "== Plain-secret scan of committed text (must be empty):"
(cd "$DEST" && git grep -nE 'ATATT3x|change-me|~\?~[A-Za-z0-9]{10,}|MULE_SECURE_KEY=[A-Za-z0-9]{16}' -- . ':!docs/*' ':!tools/*' ':!*.md' || true)
echo "== Next: create the GitHub repository and push:  gh repo create <owner>/$REPO_NAME --private --source \"$DEST\" --remote origin --push"
