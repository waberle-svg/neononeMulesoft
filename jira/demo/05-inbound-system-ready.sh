#!/bin/zsh
# Step 5 — inbound: move the ticket to "System Ready" in Jira, run the sweep, show the Account got stamped.
source "$(dirname "$0")/demo-env.sh"; source "$(dirname "$0")/.last-demo.env"
[ -n "$KEY" ] || { echo "no ticket key recorded — run 04-watch.sh first"; exit 1; }
TOOL="$ROOT/tools/secure-properties-tool.jar"; Y="$ROOT/jira-sys-api/src/main/resources/config/secure-dev.yaml"
dec(){ v=$(grep -E "^\s*$1:" "$Y" | sed -E 's/.*!\[([^]]*)\].*/\1/'); "$JAVA_HOME/bin/java" -cp "$TOOL" com.mulesoft.tools.SecurePropertiesTool string decrypt AES CBC "$MULE_SECURE_KEY" "$v"; }
EMAIL=$(dec email); TOKEN=$(dec token); J="https://neoncrm.atlassian.net/rest/api/3"
for step in 1 2 3 4 5; do
  cur=$(curl -s -u "$EMAIL:$TOKEN" "$J/issue/$KEY?fields=status" | python3 -c "import sys,json; s=json.load(sys.stdin)['fields']['status']; print(s['id']+'|'+s['name'])")
  echo "  $KEY is: ${cur#*|}"; [ "${cur%%|*}" = "10805" ] && break
  tid=$(curl -s -u "$EMAIL:$TOKEN" "$J/issue/$KEY/transitions" | python3 -c "
import sys,json; ts=json.load(sys.stdin)['transitions']
pref=[t for t in ts if t['to']['id']=='10805'] or [t for t in ts if t['to']['name'] in ('Testing in Progress','In Progress')] or ts
print(pref[0]['id'])")
  curl -s -u "$EMAIL:$TOKEN" -o /dev/null -X POST "$J/issue/$KEY/transitions" -H "Content-Type: application/json" -d "{\"transition\":{\"id\":\"$tid\"}}"; sleep 1
done
cd "$SFDX"
echo "--- Account date before sweep: $(sfq "SELECT Neon_CRM_Instance_Created_Date__c FROM Account WHERE Id='$ACC'" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['records'][0]['Neon_CRM_Instance_Created_Date__c'])")"
echo "--- running the sweep (normally hourly) ---"
curl -s --max-time 120 -X POST http://localhost:8083/api/v1/sweeps/instance-ready | tr -d '\n ' ; echo; sleep 6
echo "--- after ---"
sfq "SELECT JIRA_SETUP_Status__c, JIRA_SETUP_Status_Updated__c FROM Opportunity WHERE Id='$OPP'" | python3 -c "import sys,json; r=json.load(sys.stdin)['result']['records'][0]; print(f\"  Opportunity status: {r['JIRA_SETUP_Status__c']} at {r['JIRA_SETUP_Status_Updated__c']}\")"
echo "  Account instance-created date: $(sfq "SELECT Neon_CRM_Instance_Created_Date__c FROM Account WHERE Id='$ACC'" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['records'][0]['Neon_CRM_Instance_Created_Date__c'])")"
