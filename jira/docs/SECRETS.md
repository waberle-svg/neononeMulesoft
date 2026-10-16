# Secrets: where they live and how to encrypt one

Every secret the three Mule apps need (Jira token, Jira webhook secret, Salesforce consumer key, keystore password,
inter-app shared secret) is stored **encrypted** inside the app, in `src/main/resources/config/secure-<env>.yaml`,
and is decrypted at runtime with a 16-character key that is **not** in the repository. The encrypted files are
committed; the key, the keystores and `.mule-local.env` are not (see `.gitignore`).

| What | Where |
|---|---|
| Encrypted values per environment | `<app>/src/main/resources/config/secure-dev.yaml` (`secure-uat.yaml`, `secure-prod.yaml` when those environments exist) |
| The key, locally | `.mule-local.env` (Dev) or `.mule-local-<env>.env` (UAT, Preprod, Production) at the repo root as `MULE_SECURE_KEY`, next to `INTER_APP_SECRET` (copy from the team vault; never commit, never paste in chat). `tools/env-check.sh <env>` proves every value of `secure-<env>.yaml` decrypts under it without printing anything. |
| The key, on CloudHub | Runtime Manager property `secure.key`, marked **Protected** |
| How the app uses it | `global.xml` → `<secure-properties:config file="config/secure-${mule.env}.yaml" key="${secure.key}">`; values are referenced as `${secure::jira.token}` / `p('secure::api.clientSecret')` |
| The tool | `tools/secure-properties-tool.jar` (MuleSoft Secure Properties Tool), run with the JDK 17 bundled with the MuleSoft VS Code extension |

## Encrypt a value (what to do when a secret changes)
```bash
cd ~/Desktop/Mulesoft-N-One                     # repo root
set -a; source .mule-local.env; set +a          # loads MULE_SECURE_KEY into this shell only
JAVA="$HOME/.vscode/extensions/salesforce.mule-dx-dependencies-1.7.1-darwin-arm64/build/deps/jdk-17.0.13+11/Contents/Home/bin/java"

"$JAVA" -cp tools/secure-properties-tool.jar com.mulesoft.tools.SecurePropertiesTool \
    string encrypt AES CBC "$MULE_SECURE_KEY" "<the plain value>"
```
A value typed on the command line lands in the shell history. For a token or a password, read it from the keyboard instead:
```bash
enc() { "$JAVA" -cp tools/secure-properties-tool.jar com.mulesoft.tools.SecurePropertiesTool string encrypt AES CBC "$MULE_SECURE_KEY" "$1"; }
read -rs V && enc "$V"; unset V      # paste the value, Enter: the ciphertext prints and the value never enters the history
```
The output is the ciphertext. Put it into the YAML **wrapped in `![...]`**:
```yaml
jira:
  webhookSecret: "![<ciphertext>]"
```
Then rebuild the app (`mvn clean package`) and redeploy it: the file travels inside the JAR, so a changed secret is a
new JAR, not a property change.

Check a value decrypts (prints the plain value — only in a private shell, never in a shared log):
```bash
"$JAVA" -cp tools/secure-properties-tool.jar com.mulesoft.tools.SecurePropertiesTool \
    string decrypt AES CBC "$MULE_SECURE_KEY" "<ciphertext without the ![ ] wrapper>"
```

## Rules
- The key must be exactly 16 characters (AES-128; the tool also accepts 32). Generate a new one with `openssl rand -hex 8`.
- **One key per environment.** Dev, UAT and Production each get their own key and their own `secure-<env>.yaml`, so a key
  leaked from one environment opens nothing else.
- The same value encrypted twice gives different ciphertexts (random IV); that is expected.
- Secrets that exist only in the laptop's env file (`INTER_APP_SECRET` for manual curl checks) are conveniences; the apps
  read the encrypted copy.
- If a key or secret ever appears in a chat, a log or a screenshot, treat it as compromised: generate a new one,
  re-encrypt the affected `secure-<env>.yaml` files, rebuild, redeploy, update the vault.
- MUnit uses `src/test/resources/config/secure-test.yaml` with fake values and its own key set by the Maven plugin;
  nothing from a real environment is needed to run the tests.

Related: `docs/SETUP.md` §4 (getting the key and keystore from the vault), `docs/DEPLOY.md` §3 (every secret of a new environment, end to end), KB `01-MULESOFT/03-commands-cheatsheet.md` §3.
