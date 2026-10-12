#!/bin/zsh
# env-check.sh — READ-ONLY readiness check of one environment's configuration in this repository. Prints no secret.
# It proves that <env> can be built and deployed:
#   - config-<env>.yaml present in every app; no REPLACE_ME left except the three hostnames (set in Runtime Manager, §5.2 of docs/DEPLOY.md)
#   - secure-<env>.yaml present in every app; every value encrypted (![...]); every key the app needs present
#   - the keystore config-<env>.yaml points at exists in salesforce-sys-api's keystore folder (it travels inside the JAR)
#   - nothing secret is tracked or staged (keys, keystores, env files are git-ignored)
#   - if .mule-local-<env>.env exists (Dev: .mule-local.env): every ciphertext decrypts under that key, the inter-app secret is the
#     same in the three apps (and equals INTER_APP_SECRET when set), the consumer key has Salesforce's shape, the keystore opens
#     with the decrypted password and holds the configured alias
#   - with --jars: each target/*-mule-application.jar carries config-<env>.yaml, secure-<env>.yaml and (salesforce-sys-api) the keystore
# usage: tools/env-check.sh <env> [--jars]          exit 0 = ready · 1 = fix the FAIL lines
set -u; setopt null_glob no_nomatch
ENV_NAME="${1:?environment required, e.g. uat}"; JARS="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPS=(jira-sys-api salesforce-sys-api provisioning-prc-api)
typeset -A NEED; NEED=(jira-sys-api "jira.email jira.token jira.webhookSecret api.clientSecret"
                       salesforce-sys-api "sf.consumerKey sf.keystore.password api.clientSecret"
                       provisioning-prc-api "api.clientSecret")
fail=0; warn=0
ok()   { print -r -- "OK    $1"; }
bad()  { print -r -- "FAIL  $1"; fail=$((fail+1)); }
warnf(){ print -r -- "WARN  $1"; warn=$((warn+1)); }

# Flatten a simple 2-space-indented YAML file into key.path=value lines (comments and blank lines dropped, quotes kept)
flat() { awk '
  /^[ \t]*#/ || /^[ \t]*$/ { next }
  { match($0, /^ */); ind = RLENGTH / 2
    line = $0; sub(/^ */, "", line); sub(/[ \t]+#.*$/, "", line)
    i = index(line, ":"); if (i == 0) next
    key = substr(line, 1, i - 1); val = substr(line, i + 1); sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
    path[ind] = key; for (j = ind + 1; j < 16; j++) delete path[j]
    if (val != "") { p = ""; for (j = 0; j <= ind; j++) p = p (j ? "." : "") path[j]; print p "=" val } }' "$1"; }
val() { flat "$1" | awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' | sed -E 's/^"(.*)"$/\1/'; }

print -r -- "== $ENV_NAME: configuration files"
for app in $APPS; do
  cfg="$ROOT/$app/src/main/resources/config/config-$ENV_NAME.yaml"; sec="$ROOT/$app/src/main/resources/config/secure-$ENV_NAME.yaml"
  if [ -f "$cfg" ]; then
    left=$(grep -n "REPLACE_ME" "$cfg" | grep -v -E "^[0-9]+:[[:space:]]*(host:|#)" || true)
    hosts=$(grep -c -E "^[[:space:]]*host:.*REPLACE_ME" "$cfg" | tr -d ' ')
    if [ -n "$left" ]; then bad "$app/config-$ENV_NAME.yaml still has REPLACE_ME outside the hostnames:"; print -r -- "$left" | sed 's/^/        /'; else ok "$app/config-$ENV_NAME.yaml: no REPLACE_ME outside the hostnames"; fi
    [ "$hosts" -gt 0 ] && warnf "$app/config-$ENV_NAME.yaml: $hosts hostname(s) still REPLACE_ME (set them in Runtime Manager, back-fill after the first deployment)"
  else bad "$app: config-$ENV_NAME.yaml missing"; fi
  if [ -f "$sec" ]; then
    plain=$(flat "$sec" | grep -v -E '^[^=]+="!\[[^]]+\]"$' || true)
    if [ -n "$plain" ]; then bad "$app/secure-$ENV_NAME.yaml has values that are not ![encrypted]: $(print -r -- "$plain" | cut -d= -f1 | tr '\n' ' ')"; else ok "$app/secure-$ENV_NAME.yaml: every value is ![encrypted]"; fi
    for k in ${=NEED[$app]}; do [ -n "$(val "$sec" "$k")" ] || bad "$app/secure-$ENV_NAME.yaml: key $k missing"; done
    # the app only hides properties it declares as secure: every key here must be listed in mule-artifact.json
    for k in $(flat "$sec" | cut -d= -f1); do grep -q "\"$k\"" "$ROOT/$app/mule-artifact.json" || warnf "$app: $k is not listed under secureProperties in mule-artifact.json"; done
  else bad "$app: secure-$ENV_NAME.yaml missing (see docs/SECRETS.md and KB 34)"; fi
done

print -r -- "== $ENV_NAME: keystore"
sfcfg="$ROOT/salesforce-sys-api/src/main/resources/config/config-$ENV_NAME.yaml"
kspath=$(val "$sfcfg" "sf.keystore.path"); ksalias=$(val "$sfcfg" "sf.keystore.alias"); ks="$ROOT/salesforce-sys-api/src/main/resources/$kspath"
if [ -z "$kspath" ]; then bad "sf.keystore.path not set in config-$ENV_NAME.yaml"
elif [ -f "$ks" ]; then ok "keystore present for the build: salesforce-sys-api/src/main/resources/$kspath (alias expected: $ksalias)"
else bad "keystore missing: salesforce-sys-api/src/main/resources/$kspath — copy it from .secrets/$ENV_NAME/ (vault) before building"; fi
others=$(ls "$ROOT/salesforce-sys-api/src/main/resources/keystore/" 2>/dev/null | grep -E '\.(jks|p12)$' | grep -v "$(basename "$kspath")" || true)
[ -n "$others" ] && warnf "other keystores in the folder will travel inside the JAR too: $(print -r -- $others | tr '\n' ' ')"

print -r -- "== git hygiene"
tracked=$(git -C "$ROOT" ls-files | grep -E '\.(jks|p12|key)$|(^|/)\.mule-local.*\.env$|secure-.*\.plain\.yaml$' | grep -v munit-dummy || true)
[ -n "$tracked" ] && bad "secret-shaped files are TRACKED by git: $tracked" || ok "no keystore, key or env file is tracked by git"
staged=$(git -C "$ROOT" status --porcelain | grep -E '\.(jks|p12|key|env)$|secure-.*\.plain' || true)
[ -n "$staged" ] && bad "secret-shaped files appear in git status: $staged" || ok "git status shows no keystore, key or env file"

print -r -- "== $ENV_NAME: decryption (only when the env file is on this machine)"
envfile="$ROOT/.mule-local-$ENV_NAME.env"; [ "$ENV_NAME" = "dev" ] && [ ! -f "$envfile" ] && envfile="$ROOT/.mule-local.env"
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/java}"; [ -x "${JAVA:-/nonexistent}" ] || JAVA=$(ls -d ~/.vscode/extensions/salesforce.mule-dx-dependencies-*/build/deps/jdk-17*/Contents/Home/bin/java 2>/dev/null | head -1); [ -x "${JAVA:-/nonexistent}" ] || JAVA=$(command -v java || true)
if [ ! -f "$envfile" ]; then warnf "no $(basename "$envfile") here: decryption not checked (fine on a machine that must not hold the key)"
elif [ -z "$JAVA" ]; then warnf "no java found: decryption not checked"
else
  set -a; source "$envfile"; set +a
  dec() { "$JAVA" -cp "$ROOT/tools/secure-properties-tool.jar" com.mulesoft.tools.SecurePropertiesTool string decrypt AES CBC "$MULE_SECURE_KEY" "$1" 2>/dev/null; }
  [ "${#MULE_SECURE_KEY}" -eq 16 ] || [ "${#MULE_SECURE_KEY}" -eq 32 ] && ok "MULE_SECURE_KEY has ${#MULE_SECURE_KEY} characters" || bad "MULE_SECURE_KEY must be 16 (or 32) characters, has ${#MULE_SECURE_KEY}"
  typeset -A cs
  for app in $APPS; do
    sec="$ROOT/$app/src/main/resources/config/secure-$ENV_NAME.yaml"; [ -f "$sec" ] || continue
    for k in ${=NEED[$app]}; do
      c=$(val "$sec" "$k"); c="${c#!\[}"; c="${c%\]}"; [ -n "$c" ] || continue
      p=$(dec "$c"); rc=$?
      if [ $rc -ne 0 ] || [ -z "$p" ]; then bad "$app: $k does not decrypt with this key (wrong key, or the value was encrypted under another one)"; continue; fi
      case "$k" in
        api.clientSecret)     cs[$app]="$p"; ok "$app: api.clientSecret decrypts (${#p} characters)";;
        sf.consumerKey)       [[ "$p" == 3MVG* ]] && ok "$app: sf.consumerKey decrypts and has a Salesforce consumer key's shape" || bad "$app: sf.consumerKey decrypts but does not look like a Salesforce consumer key (expected to start with 3MVG)";;
        sf.keystore.password) if [ -f "$ks" ]; then "${JAVA:h}/keytool" -list -keystore "$ks" -storepass "$p" -alias "$ksalias" >/dev/null 2>&1 && ok "salesforce-sys-api: keystore password decrypts, opens the keystore and alias $ksalias is there" || bad "salesforce-sys-api: the decrypted keystore password does not open $kspath with alias $ksalias"; else warnf "keystore password decrypts; keystore not present to open"; fi;;
        jira.email)           [[ "$p" == *@* ]] && ok "jira-sys-api: jira.email decrypts (an e-mail address)" || bad "jira-sys-api: jira.email decrypts but is not an e-mail address";;
        jira.token)           [ "${#p}" -ge 20 ] && ok "jira-sys-api: jira.token decrypts (${#p} characters)" || bad "jira-sys-api: jira.token decrypts but is suspiciously short (${#p})";;
        jira.webhookSecret)   [ "${#p}" -ge 16 ] && ok "jira-sys-api: jira.webhookSecret decrypts (${#p} characters)" || bad "jira-sys-api: jira.webhookSecret decrypts but is shorter than 16 characters";;
      esac
    done
  done
  if [ "${#cs}" -eq 3 ]; then
    if [ "${cs[jira-sys-api]}" = "${cs[salesforce-sys-api]}" ] && [ "${cs[jira-sys-api]}" = "${cs[provisioning-prc-api]}" ]; then ok "inter-app secret is identical in the three apps"; else bad "inter-app secret differs between apps (401 UNAUTHORIZED_CALLER at runtime)"; fi
    if [ -n "${INTER_APP_SECRET:-}" ]; then [ "${cs[jira-sys-api]}" = "$INTER_APP_SECRET" ] && ok "inter-app secret equals INTER_APP_SECRET in $(basename "$envfile")" || bad "inter-app secret in the apps differs from INTER_APP_SECRET in $(basename "$envfile")"; fi
  fi
  unset MULE_SECURE_KEY INTER_APP_SECRET p c cs
fi

if [ "$JARS" = "--jars" ]; then
  print -r -- "== $ENV_NAME: packaged JARs (built from $(git -C "$ROOT" rev-parse --short HEAD) if the working tree was not changed since)"
  for app in $APPS; do
    jars=("$ROOT/$app/target/$app-"*-mule-application.jar(N)); jar="${jars[1]:-}"
    if [ -z "$jar" ]; then bad "$app: no target/*-mule-application.jar (run mvn -B clean package -DskipTests)"; continue; fi
    lst=$(unzip -l "$jar")
    print -r -- "$lst" | grep -q "config/config-$ENV_NAME.yaml" && ok "$app JAR carries config-$ENV_NAME.yaml ($(date -r "$jar" '+%Y-%m-%d %H:%M'))" || bad "$app JAR lacks config/config-$ENV_NAME.yaml"
    print -r -- "$lst" | grep -q "config/secure-$ENV_NAME.yaml" && ok "$app JAR carries secure-$ENV_NAME.yaml" || bad "$app JAR lacks config/secure-$ENV_NAME.yaml"
    if [ "$app" = "salesforce-sys-api" ]; then
      print -r -- "$lst" | grep -q " $kspath$" && ok "$app JAR carries $kspath" || bad "$app JAR lacks $kspath (copy the keystore into src/main/resources/keystore/ and rebuild)"
      extra=$(print -r -- "$lst" | grep -E 'keystore/.*\.(jks|p12)$' | awk '{print $NF}' | grep -v "^$kspath$" || true)
      [ -n "$extra" ] && warnf "$app JAR also carries other keystores: $(print -r -- $extra | tr '\n' ' ')"
    fi
  done
fi

print -r -- "== result: $fail FAIL, $warn WARN"
[ "$fail" -eq 0 ]
