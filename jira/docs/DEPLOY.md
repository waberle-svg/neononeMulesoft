# Environments, builds, deployments and promotion

How the three Mule apps reach UAT, Preprod and Production from one `main`. UAT is the worked example; Preprod and
Production repeat it. Companion docs: `docs/SECRETS.md` (how one value is encrypted), `docs/BRANCHING.md` (branches,
PRs, tags), the knowledge base NEONONE-KB 34 (secrets for a new environment), 36 (certificate and keystore per
environment), 35 (Salesforce side of UAT), 32 (UAT plan and acceptance run).

## 1. How environments work

One repository, one `main`, no environment branches and no environment repositories. A deployment is a pair: a
commit and an environment. The commit is named by a Git tag `<env>/<yyyy-mm-dd>`; the environment is named by the
Runtime Manager property `mule.env`, which makes the app read `config-<env>.yaml` and `secure-<env>.yaml` from inside
its own JAR.

| Layer | Where it lives | In Git? | Differs per environment? |
|---|---|---|---|
| Code: flows, DataWeave, mappings, RAML | `src/main/mule`, `src/main/resources` | yes | never |
| Non-secret settings | `src/main/resources/config/config-<env>.yaml` | yes | yes, one file per environment |
| Secrets, encrypted as `![...]` | `src/main/resources/config/secure-<env>.yaml` | yes | yes, one file per environment, each under its own AES key |
| AES key, 16 characters | team vault; Runtime Manager property `secure.key` (protected) | never | yes |
| Salesforce JWT keystore (`.jks`) | vault; copied to `salesforce-sys-api/src/main/resources/keystore/` before a build | never | yes |
| Runtime Manager properties | the app's Properties tab | no | yes: `mule.env`, `secure.key`, the three hostnames |

**What moves between environments:** the commit, which already carries every environment's config and encrypted
secrets. **What never moves:** keys, keystores, tokens, consumer keys and Runtime Manager properties. Promoting
therefore means building the same commit again with the next environment's keystore and uploading the JARs to that
environment's apps. The JAR is built once per environment only because the keystore travels inside it; everything
else in two builds of one commit is identical.

**A change travels like this.** A feature branch off `main`, a pull request, a merge. Dev is updated from the merge
commit and tagged `dev/<date>`. When Dev has proven it, the same commit is built for UAT and uploaded to the `-uat`
apps, tagged `uat/<date>`. Preprod and Production repeat that from the same commit. UAT may lag behind `main`: it is
always built from the commit a tag names, never from "whatever `main` is today". Nothing is edited on the way; a
value that must differ in UAT is a line in `config-uat.yaml`, merged first, built second.

**Two rules that keep this honest.** The three apps of one environment are built from one commit, and one tag names
it (Dev's three apps were built from three commits before this rule existed; the first UAT deployment starts the
rule). And `main` stays releasable: a merge that is not ready for the next environment waits on its branch.

## 2. Environment matrix

| | Dev | UAT | Preprod | Production |
|---|---|---|---|---|
| Anypoint environment | Sandbox (shared with the Rocketlane team's `sf-to-rocketlane-dev`) | Sandbox, app names suffixed `-uat`, until the client provides a UAT environment | to decide with the client | to decide with the client |
| App names | `jira-sys-api-dev`, `salesforce-sys-api-dev`, `provisioning-prc-api-dev` | `jira-sys-api-uat`, `salesforce-sys-api-uat`, `provisioning-prc-api-uat` | `…-preprod` | `…-prod` |
| `mule.env` | `dev` | `uat` | `preprod` | `prod` |
| Config pair | `config-dev.yaml` + `secure-dev.yaml` | `config-uat.yaml` + `secure-uat.yaml` | `config-preprod.yaml` + `secure-preprod.yaml` (both to create) | `config-prod.yaml` (exists, placeholders) + `secure-prod.yaml` (to create) |
| Salesforce org | Dev sandbox `cpqtriage` | sandbox `rcaimplem`, `https://neonone--rcaimplem.sandbox.my.salesforce.com` | Preprod sandbox (name tbc) | Production |
| `sf.tokenEndpoint` | `https://test.salesforce.com/services/oauth2/token` | same | same | `https://login.salesforce.com/services/oauth2/token` |
| `sf.principal` (JWT subject) | Ayush's Dev user | `swati.sharma@bluvium.com.rcaimplem` for now; the integration user when the client creates one | integration user | integration user |
| Keystore alias | `neon-jira-integration-dev` | `neon-jira-integration-uat` | `neon-jira-integration-preprod` | `neon-jira-integration-prod` |
| Jira site | `neoncrm.atlassian.net` | same | same | same |
| Jira API identity (`jira.email` + `jira.token`) | Swati's account | Swati's account, a separate token for UAT, for now | service account (client) | service account (client) |
| Jira projects | NSSU (setup), WOU (deactivation) | NSSU, WOU | tbc, NSSU/WOU unless the client says otherwise | SETUP, WORK (FUND/ARTS tbc) |
| Reporters (`reporters.*`) | Swati | Swati for now; Natalie (CRM setup) and Chelsea (deactivation) once the client confirms their project access | per client | Natalie / Chelsea per the requirements |
| Label prefixes | `sf-setup`, `sf-deact` | `sf-setup-uat`, `sf-deact-uat` | `sf-setup-preprod`, `sf-deact-preprod` | `sf-setup`, `sf-deact` |
| Secure key holder | Ayush (vault) | Ayush (vault); handed to the deployer through the client's vault | the deployer | the deployer |
| Jira webhook | registered (Dev URL) | to register once the app is Running | to register | to register |

Label prefixes differ per environment because Dev, UAT and Preprod may share the Jira projects NSSU and WOU: the
duplicate check searches Jira by label, and an environment must only ever find its own tickets.

## 3. Prepare a new environment, once

### 3.1 Salesforce side first (Salesforce admin; KB 35 and 36)
Package 1 deployed to the org; the External Client App created by hand with **this environment's** certificate;
its policies set (admin-approved users pre-authorised, permission set `Jira_Integration_Access` attached, IP
relaxation per the client's answer); the consumer key in the vault; the principal user active, API-enabled, holding
`Jira_Integration_Access` (directly or through a group). Without these, `salesforce-sys-api` cannot log in and
will not start cleanly.

### 3.2 Secrets and keystore (KB 34 and 36)
| Secret | How it is made | Where the plain value lives | Goes into |
|---|---|---|---|
| Secure key `MULE_SECURE_KEY_<ENV>` | `openssl rand -hex 8` (16 characters) | vault; `.mule-local-<env>.env` | Runtime Manager `secure.key` (protected) on all three apps |
| Inter-app secret `INTER_APP_SECRET_<ENV>` | `openssl rand -hex 32` | vault; `.mule-local-<env>.env` | `api.clientSecret` in all three `secure-<env>.yaml` |
| Webhook secret | `openssl rand -hex 32` | vault (the Jira admin needs it) | `jira.webhookSecret` in jira-sys-api |
| Jira API token | the Jira identity's Atlassian account ▸ Security ▸ API tokens ▸ create, label `neonone-mule-<env>`, expiry at most 1 year | vault | `jira.email`, `jira.token` in jira-sys-api |
| Keystore + password | KB 36 (`keytool`, alias `neon-jira-integration-<env>`) | vault; `.secrets/<env>/` | the JAR (keystore); `sf.keystore.password` in salesforce-sys-api |
| Consumer key | generated by Salesforce when the External Client App is created (3.1) | vault | `sf.consumerKey` in salesforce-sys-api |

Local layout (all git-ignored): `.mule-local-<env>.env` with `MULE_SECURE_KEY` and `INTER_APP_SECRET`;
`.secrets/<env>/neon-jira-integration-<env>.jks`, `.crt`, `keystore-<env>.env` with `SF_<ENV>_KEYSTORE_PASSWORD`.

### 3.3 Repository changes, on a branch `feature/<env>-environment-config`
1. `config-<env>.yaml` in each app. Dev, UAT and Production files exist; Preprod is created by copying the UAT file
   and changing every environment-specific key:

   | App | Keys to set |
   |---|---|
   | `salesforce-sys-api` | `sf.tokenEndpoint`, `sf.principal`, `sf.keystore.path`, `sf.keystore.alias`, `sf.events.allowSimulation` (`"false"` outside Dev) |
   | `jira-sys-api` | `jira.defaults.project`, `jira.defaults.assigneeAccountId`, `jira.screens.DEACTIVATE_INSTANCE` (per target project) |
   | `provisioning-prc-api` | `sf.baseUrl`, `provisioning.labelPrefix`, `deactivation.labelPrefix`, `deactivation.lines.*.project`, `reporters.*`, `jira.project` |

   The three hostnames (`prc.host`, `sysSf.host`, `sysJira.host`) stay `REPLACE_ME_…` until the apps exist: they are
   set as Runtime Manager properties at the first deployment and written back into the file afterwards (§5.2).
2. `secure-<env>.yaml` in each app, new, copying the comment layout of `secure-dev.yaml`; every value encrypted under
   this environment's key (`docs/SECRETS.md`). Keys: jira-sys-api `jira.email`, `jira.token`, `jira.webhookSecret`,
   `api.clientSecret`; salesforce-sys-api `sf.consumerKey`, `sf.keystore.password`, `api.clientSecret`;
   provisioning-prc-api `api.clientSecret`. Template (keep only the blocks the app needs):
   ```yaml
   # <app> — <ENV> secrets, encrypted with the Secure Configuration Properties module (AES/CBC) under the <ENV> key.
   # The key is supplied at runtime as the protected Runtime Manager property secure.key (locally from .mule-local-<env>.env).
   jira:                      # jira-sys-api only
     email: "![...]"
     token: "![...]"
     webhookSecret: "![...]"
   sf:                        # salesforce-sys-api only
     consumerKey: "![...]"
     keystore:
       password: "![...]"
   api:                       # all three apps: the same inter-app secret
     clientSecret: "![...]"
   ```
3. `.secrets/README.md`: one line for the new environment's keystore.
4. `tools/env-check.sh <env>` → no FAIL lines. Then `mvn -B clean test` in each app, push, pull request. The reviewer
   checks that the diff holds no plain secret and no keystore. Merge.

## 4. Build for an environment
```bash
cd ~/Desktop/Mulesoft-N-One
git fetch --tags origin
git checkout <commit or tag>                     # the merge commit on main, or an existing tag such as uat/2026-10-14
cp .secrets/<env>/neon-jira-integration-<env>.jks salesforce-sys-api/src/main/resources/keystore/
for app in jira-sys-api salesforce-sys-api provisioning-prc-api; do (cd $app && mvn -B clean package -DskipTests) || break; done
tools/env-check.sh <env> --jars                  # config + secure files + keystore inside each JAR
git rev-parse --short HEAD                       # the commit the JARs were built from: goes into the tag message
git checkout main
```
The JARs are `<app>/target/<app>-1.0.0-SNAPSHOT-mule-application.jar`. MUnit ran on the pull request, so a promoted
commit is packaged with `-DskipTests`; a commit that never went through a PR gets `mvn -B clean test` first. The JAR
carries every `.jks` in the keystore folder: for a Production build keep only the Production keystore there.

## 5. Deploy in Runtime Manager

### 5.1 First deployment of an environment (create the three apps)
Runtime Manager ▸ the environment ▸ Applications ▸ **Deploy application**, in the order **jira-sys-api → salesforce-sys-api → provisioning-prc-api**.
Target CloudHub 2.0 ▸ Shared Space ▸ Cloudhub-US-East-2; runtime 4.12.3 (Java 17); 1 replica, 0.1 vCore; runtime
cluster mode off; **Object Store v2 on**; update strategy rolling; "Use Persistent Object Storage" off; Ingress:
generate default public URL, path `/`, last-mile security off. Upload the JAR with **Import file**. Properties
(names are case-sensitive; hosts are hostnames only, no scheme, path or trailing slash):

| Property | `jira-sys-api-<env>` | `salesforce-sys-api-<env>` | `provisioning-prc-api-<env>` | Protected |
|---|---|---|---|---|
| `mule.env` | `<env>` | `<env>` | `<env>` | no |
| `secure.key` | the 16-character key | same | same | **yes** |
| `http.port` | `8081` | `8081` | `8081` | no |
| `api.enforceClientSecret` | `true` | `true` | `true` | no |
| `prc.protocol` / `prc.host` / `prc.port` | `HTTPS` / prc host (`localhost` until it exists) / `443` | same | — | no |
| `sysSf.protocol` / `sysSf.host` / `sysSf.port` | — | — | `HTTPS` / salesforce-sys-api host / `443` | no |
| `sysJira.protocol` / `sysJira.host` / `sysJira.port` | — | — | `HTTPS` / jira-sys-api host / `443` | no |

`http.port` and `api.enforceClientSecret` already hold these values in `config-<env>.yaml`; setting them again keeps
the sheet identical to Dev. Status goes Applying → Running in 2–5 minutes.

### 5.2 Host back-fill
A CloudHub 2.0 public hostname has the shape `<app name>-<suffix>.usa-e2.cloudhub.io` (Dev:
`jira-sys-api-dev-7e6zq2.5sc6y6-2.usa-e2.cloudhub.io`); the suffix is assigned at creation, so it cannot be
predicted. When all three apps are Running, copy each app's hostname from its page, set the host properties on the
other apps and **Apply changes** (jira and sf get `prc.host`; prc already has both system hosts if the system apps
were created first). Then open a small pull request that writes the three hostnames into `config-<env>.yaml`
(`prc.host`, `sysSf.host`, `sysJira.host`) so the file is the record and a redeployment from scratch needs no memory
of the properties; the properties stay, with the same values.

### 5.3 Updating a running app
App ▸ Settings ▸ Application File ▸ **Upload** the new JAR ▸ **Apply changes**. Properties are untouched and survive
the update; rolling update keeps the old replica serving until the new one is Running. A rotated secure key is the
one case that needs both a new JAR and a new `secure.key` value (KB 34, Rotation).

### 5.4 Jira webhook (Jira admin, after jira-sys-api is Running)
URL `https://<jira-sys-api-<env> host>/api/v1/webhooks/jira`; secret = this environment's webhook secret from the
vault (Jira signs each call with HMAC-SHA256 in `X-Hub-Signature`, the app rejects anything else); JQL `project in
(NSSU, WOU)` (Production: `project in (SETUP, WORK)`); event *Issue updated*. Register it only once the app is
Running; before that Jira retries and gives up.

## 6. Verify
```bash
set -a; source .mule-local-<env>.env; set +a          # INTER_APP_SECRET for the header; nothing is printed
for h in <jira host> <sf host> <prc host>; do curl -s -H "X-Client-Secret: $INTER_APP_SECRET" "https://$h/api/v1/ping"; echo; done
```
Each app answers `{"status":"ok","app":"<name>","version":"1.0.0","env":"<env>",…}`; without the header the answer
is 401. Logs: salesforce-sys-api shows the JWT login and the subscription to `/event/Integration_Request__e`, and no
`invalid_client_id`, `invalid_grant`, keystore or decryption error; `GET /api/v1/me` on jira-sys-api (same header)
returns the token's user; `GET /api/v1/retry-queue` on provisioning-prc-api is empty. The first transaction follows
KB 32 §7 (a test Order in the Salesforce org, Flows active there).

## 7. Tag and record
```bash
git fetch origin && git checkout main && git pull
git tag -a uat/2026-10-14 <commit> -m "UAT: jira-sys-api <RM version>, salesforce-sys-api <RM version>, provisioning-prc-api <RM version>"
git push origin uat/2026-10-14
git tag -l 'uat/*'                                   # every UAT deployment, by date
git show --no-patch uat/2026-10-14                   # who, when, which commit, which versions
```
A second deployment on the same day is `uat/2026-10-14-2`. The RM version is the application version Runtime
Manager shows after the upload (Dev today: jira 1.0.5, sf 1.0.6, prc 1.0.10). Add a row to the deployment log
(§9) and to the knowledge base build log.

## 8. Promote, roll back, change a setting
- **Promote** UAT → Preprod: `git checkout uat/<date>`, §4 with the Preprod keystore, §5.3 (or §5.1 the first time)
  on the Preprod apps, tag `preprod/<date>` on the same commit. `git log --oneline preprod/<previous>..preprod/<new>`
  lists exactly what the new deployment brings.
- **Roll back**: `git checkout <previous tag>`, §4, §5.3 on the affected apps; tag the running commit again
  (`<env>/<date>` with "rollback to `<previous tag>`" in the message) so the tags always name what runs. Properties
  and Object Store contents are untouched by a JAR change.
- **Change a setting** (a reporter id, a retry delay): edit `config-<env>.yaml` on a branch, pull request, merge,
  build, upload, tag. A configuration change is a deployment like any other.
- **Urgent override without a rebuild**: any key of `config-<env>.yaml` can be set as a Runtime Manager property
  with the same name (`reporters.setup.lines.NEON_CRM`, for example) and applied in a minute. Make the file match
  in the next pull request; the property and the file must never disagree for long.
- **Hotfix while `main` holds unreleased work**: branch `hotfix/<topic>` from the environment's tag, pull request
  into `main` as usual; build the hotfix from its merge commit only if `main` is releasable, otherwise build from
  the hotfix branch head and tag that commit. Prefer keeping `main` releasable so this case never arises.

## 9. Deployment log
| Date | Env | Tag | Commit | jira-sys-api | salesforce-sys-api | provisioning-prc-api | By | Note |
|---|---|---|---|---|---|---|---|---|
| 2026-10-07 | dev | `dev/sf/2026-10-07` | `d8889fb` | — | `7e95cf31` (RM 1.0.6) | — | Ayush | tracking fields, history layout (PR #14) |
| 2026-10-08 | dev | `dev/jira/2026-10-08` | `2468178` | `4ca62cd3` (RM 1.0.5) | — | — | Ayush | description formatting (PR #16) |
| 2026-10-09 | dev | `dev/prc/2026-10-09` | `8ba2963` | — | — | `9ce25f07` (RM 1.0.10) | Ayush | footer and Order section removed (PR #17) |

Dev's rows are per app because its apps were deployed one at a time; from UAT on, one row per environment
deployment. The three Dev tags are the one-time exception, created so that history is named too:
```bash
git tag -a dev/sf/2026-10-07   d8889fb -m "Dev: salesforce-sys-api 7e95cf31 (RM 1.0.6)"
git tag -a dev/jira/2026-10-08 2468178 -m "Dev: jira-sys-api 4ca62cd3 (RM 1.0.5)"
git tag -a dev/prc/2026-10-09  8ba2963 -m "Dev: provisioning-prc-api 9ce25f07 (RM 1.0.10)"
git push origin --tags
```
