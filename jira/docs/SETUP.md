# Developer setup guide — Neon One MuleSoft integration (Mulesoft-N-One)

For Bluvium developers joining the Neon One Salesforce ↔ Jira integration. Assumes a blank laptop (macOS; Windows notes at the end) and no MuleSoft experience. Follow it top to bottom; every step ends with a check. Expect about two hours including downloads. This file is also committed to the repository as `docs/SETUP.md`.

## 0. What you are setting up
Three Mule 4 applications (`salesforce-sys-api`, `jira-sys-api`, `provisioning-prc-api`) that run on Mule runtime **4.12.3 / Java 17**, are built with **Maven**, tested with **MUnit**, and deployed to **CloudHub 2.0** (private space *Bluvium*, Anypoint organisation *Neon One*). Configuration is per environment in YAML; secrets are AES-encrypted in the repo and decrypted at runtime with a key you receive out of band. Architecture and decisions: knowledge base `NEONONE-KB` (ask Ayush for access), especially `02-PROJECT-NEONONE-SF-JIRA/02-architecture.md` and `03-architecture-decisions.md`.

## 1. Accounts and access to request on day one
| What | From whom | Needed for |
|---|---|---|
| GitHub access to `Mulesoft-N-One` (read + PR) | Ayush | code |
| **Anypoint Platform** user in the Neon One org, roles *Cloudhub Admin (Sandbox)*, *Exchange Contributors*, *API Creators* | Neon One admin (William Aberle) via Swati/Ayush | Runtime Manager, deployments |
| Password-manager vault **"Neon One – MuleSoft"** | Ayush / Swati | `MULE_SECURE_KEY`, `INTER_APP_SECRET`, keystore file + password, connected-app id/secret, Jira token |
| Salesforce Dev sandbox user (System Administrator) | Neon One Salesforce admin | end-to-end tests only |
| Jira Cloud (neoncrm.atlassian.net) access to project NSSU | Neon One Jira admin | seeing the tickets |

Never paste any of these values into chat, tickets, commits or documentation.

## 2. Base tools
1. **Git** — `git --version` (macOS: install Xcode command-line tools when prompted).
2. **GitHub CLI** — `brew install gh` then `gh auth login` (SSH). Check: `gh auth status`.
3. **VS Code** — https://code.visualstudio.com. Move it to `/Applications` (running it from Downloads breaks the `code` command).
4. **MuleSoft Extension Pack** (Anypoint Code Builder) in VS Code: Extensions ▸ search *MuleSoft Extension Pack* by Salesforce ▸ Install. It downloads a **bundled JDK 17 and Maven 3.9.4** into `~/.vscode/extensions/salesforce.mule-dx-dependencies-<version>-<platform>/build/deps/`. Check: that folder contains `jdk-17…` and `apache-maven-3.9.4`.
5. Sign in to Anypoint from the extension when prompted (Command Palette ▸ *MuleSoft: Login to Anypoint Platform*).
6. When the extension offers to download a **Mule runtime**, choose **4.12.3**. It lands in `~/AnypointCodeBuilder/runtime/mule-enterprise-standalone-4.12.3`. Check: `ls ~/AnypointCodeBuilder/runtime`.
7. Optional but recommended: **Salesforce CLI** (`npm i -g @salesforce/cli`) for end-to-end tests, and **jq** (`brew install jq`).

Put the bundled tools on your PATH for terminal builds (adjust the version folder):
```bash
# ~/.zshrc
export MULE_DEPS="$HOME/.vscode/extensions/salesforce.mule-dx-dependencies-1.7.1-darwin-arm64/build/deps"
export JAVA_HOME="$MULE_DEPS/jdk-17.0.13+11/Contents/Home"
export PATH="$MULE_DEPS/apache-maven-3.9.4/bin:$JAVA_HOME/bin:$PATH"
```
Check: `java -version` prints 17, `mvn -v` prints 3.9.4 and Java 17. Do **not** use a system Java 21+ for Mule builds.

## 3. Clone and open the repository
```bash
cd ~/Projects   # any folder without spaces is fine
gh repo clone <owner>/Mulesoft-N-One
cd Mulesoft-N-One
```
Open **the workspace file**, not the folder: File ▸ Open Workspace from File ▸ `Mulesoft-N-One.code-workspace`. The MuleSoft extension needs each Mule project to be a workspace root; the multi-root workspace gives it that. If you open the parent folder instead you will see "Mule project must be at workspace root" and the canvas/metadata views stay empty — that is expected, not a bug.

Repository layout:
```
Mulesoft-N-One/
  Mulesoft-N-One.code-workspace   ← open this
  jira-sys-api/                   ← Mule app (pom.xml, src/main/mule, src/main/resources, src/test/munit)
  salesforce-sys-api/             ← Mule app
  provisioning-prc-api/           ← Mule app
  demo/                           ← end-to-end demo scripts (local runtime + Salesforce CLI)
  tools/                          ← secure-properties-tool.jar, helper scripts
  docs/                           ← this guide, branching rules
  .secrets/                       ← git-ignored; you create it locally (see §4)
  .mule-local.env                 ← git-ignored; you create it locally (see §4)
```

## 4. Local secrets (never committed)
Create the two ignored items from the password-manager vault:
```bash
cat > .mule-local.env <<'EOF'
MULE_SECURE_KEY=<16-character key from the vault>
INTER_APP_SECRET=<value from the vault>
EOF
chmod 600 .mule-local.env
mkdir -p .secrets/dev salesforce-sys-api/src/main/resources/keystore
# copy neon-jira-integration-dev.jks from the vault into BOTH folders:
#   .secrets/dev/neon-jira-integration-dev.jks                       (master copy)
#   salesforce-sys-api/src/main/resources/keystore/neon-jira-integration-dev.jks  (packaged into the JAR)
```
Why two copies: the JAR must contain the keystore to run on CloudHub; `*.jks` is git-ignored everywhere, so each developer places it. Check: `unzip -l salesforce-sys-api/target/*.jar | grep keystore` after the first build.

Maven credentials for deployments (`~/.m2/settings.xml`, values from the vault; the literal `~~~Client~~~` and `~?~` are MuleSoft's convention):
```xml
<settings xmlns="http://maven.apache.org/SETTINGS/1.1.0">
  <servers>
    <server>
      <id>anypoint-exchange-v3</id>
      <username>~~~Client~~~</username>
      <password>CLIENT_ID~?~CLIENT_SECRET</password>
    </server>
  </servers>
  <profiles>
    <profile>
      <id>anypoint-neon</id>
      <properties>
        <anypoint.client.id>CLIENT_ID</anypoint.client.id>
        <anypoint.client.secret>CLIENT_SECRET</anypoint.client.secret>
      </properties>
    </profile>
  </profiles>
  <activeProfiles><activeProfile>anypoint-neon</activeProfile></activeProfiles>
</settings>
```
Check: `mvn help:effective-settings -q` prints nothing (no error).

## 5. Build and test
```bash
for app in jira-sys-api salesforce-sys-api provisioning-prc-api; do
  (cd $app && mvn -B clean test) || break
done
```
Expected: `Tests run: 9`, `10`, `11` — all green — and `BUILD SUCCESS`. First run downloads dependencies (several minutes). Package without re-running tests: `mvn -B package -DskipTests` inside an app → `target/<app>-1.0.0-SNAPSHOT-mule-application.jar`.

## 6. Run locally (optional, for end-to-end work)
```bash
source .mule-local.env
RT=~/AnypointCodeBuilder/runtime/mule-enterprise-standalone-4.12.3
cp */target/*-mule-application.jar $RT/apps/
JAVA_HOME=$JAVA_HOME $RT/bin/mule -M-Dmule.env=dev -M-Dsecure.key="$MULE_SECURE_KEY"
```
Ports: 8081 salesforce-sys-api, 8082 jira-sys-api, 8083 provisioning-prc-api. Check: `curl -s localhost:8083/api/v1/ping`. The `demo/` scripts automate a full loop but **touch the client's Salesforce sandbox and Jira** — run them only with Ayush's go, never two people at once.

## 7. How the code is organised (10-minute orientation)
- `global.xml` — all connector and property configuration; `<app>.xml` — HTTP listener, caller check, APIkit router, one thin flow per RAML operation; `implementation/*.xml` — the work; `common/error-handler.xml` — one canonical error `{code, message, retryable, correlationId, detail}`.
- `src/main/resources/api/*.raml` — the contract; APIkit generates flow names like `post:\issues:application\json:jira-sys-api-config`.
- `config/config-<env>.yaml` — non-secret settings selected by `mule.env`; `config/secure-<env>.yaml` — encrypted secrets (`![...]`) read via `${secure::name}`; `mule.env` and `secure.key` are supplied at runtime.
- `src/test/munit` — tests mock every backend call by `doc:name`; `src/test/resources/config` holds fake plain test values.
- Encrypt a new secret: `java -cp tools/secure-properties-tool.jar com.mulesoft.tools.SecurePropertiesTool string encrypt AES CBC "$MULE_SECURE_KEY" "<value>"` → paste as `"![<output>]"`.

## 8. Working rules (see `docs/BRANCHING.md`)
- Never commit to `main`. Branch `feature/<ticket-or-topic>` → PR → one review → squash-merge.
- Before opening a PR: `mvn clean test` green in every app you touched; no secret values, keystores or `target/` in the diff (`git status` should never show `.secrets`, `*.env`, `*.jks`).
- Commit messages: `<app>: <what changed, imperative>` — e.g. `jira-sys-api: add caller check to main flow`.
- Deployments to CloudHub are done from `main` only, and announced in the team channel before and after.
- Record what you learned: errors and fixes go to the knowledge base (`03-RUNBOOK/ERRORS-AND-FIXES.md`), decisions to the ADR log.

## 9. Verify you are done
- [ ] `mvn -v` shows Maven 3.9.4 on Java 17
- [ ] Workspace opens with three Mule projects and the canvas renders a flow
- [ ] All three test suites green
- [ ] `salesforce-sys-api` JAR contains `keystore/neon-jira-integration-dev.jks`
- [ ] `~/.m2/settings.xml` passes `mvn help:effective-settings -q`
- [ ] You can log in to Anypoint and see Runtime Manager ▸ Sandbox
- [ ] You know where the vault is and that nothing from it goes into Git

## Windows notes
Use **Git Bash** or **WSL** for the shell snippets (`demo/*.sh` and `tools/*.sh` are zsh/bash scripts). The bundled tools live under `%USERPROFILE%\.vscode\extensions\salesforce.mule-dx-dependencies-<version>-win32-x64\build\deps\`; set `JAVA_HOME` and `PATH` accordingly. Line endings: keep LF (`git config core.autocrlf input`).
