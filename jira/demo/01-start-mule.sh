#!/bin/zsh
# Step 1 — start the three Mule apps on the local runtime (clean start, ~40 s).
source "$(dirname "$0")/demo-env.sh"
"$RT/bin/mule" stop >/dev/null 2>&1; sleep 2
rm -rf "$RT/apps/"*
for a in jira-sys-api salesforce-sys-api provisioning-prc-api; do
  J="$ROOT/$a/target/$a-1.0.0-SNAPSHOT-mule-application.jar"
  [ -f "$J" ] || { echo "MISSING $J — build it first: \"$DEPS/apache-maven-3.9.4/bin/mvn\" -B -q -f \"$ROOT/$a/pom.xml\" clean package -DskipTests"; exit 1; }
  cp "$J" "$RT/apps/$a.jar"
done
: > "$RT/logs/mule_ee.log"
"$RT/bin/mule" start -M-Dmule.env=dev -M-Dsecure.key="$MULE_SECURE_KEY" | grep -E "running|rror"
for i in $(seq 1 90); do [ "$(grep -c "Started app" "$RT/logs/mule_ee.log" 2>/dev/null)" = "3" ] && break; sleep 2; done
sleep 6
echo "apps started: $(grep -c "Started app" "$RT/logs/mule_ee.log")/3 | event subscription: $(grep -c "Successfully subscribed" "$RT/logs/mule_ee.log")"
for p in 8081 8082 8083; do printf "  %s -> " "$p"; curl -s --max-time 20 "http://localhost:$p/api/v1/ping" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['app'],'OK, env',d['env'])" 2>/dev/null || echo "no answer"; done
printf "  Jira login -> "; curl -s --max-time 30 http://localhost:8082/api/v1/me | python3 -c "import sys,json; print(json.load(sys.stdin)['displayName'])" 2>/dev/null || echo "FAILED"
