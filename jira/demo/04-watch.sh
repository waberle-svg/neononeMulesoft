#!/bin/zsh
# Step 4 — watch the loop: registry row → Jira ticket → key on the Opportunity (usually done in ~10 s).
source "$(dirname "$0")/demo-env.sh"; source "$(dirname "$0")/.last-demo.env"
cd "$SFDX"; T0=$(date +%s)
for i in $(seq 1 24); do
  R=$(sfq "SELECT Name, Request_Status__c, External_Key__c, External_Status__c, Attempts__c, Last_Error_Short__c FROM Integration_Transaction__c WHERE Opportunity__c='$OPP' ORDER BY CreatedDate DESC LIMIT 1" | python3 -c "
import sys,json; rs=json.load(sys.stdin)['result']['records']
print('no registry row yet' if not rs else f\"{rs[0]['Name']} | {rs[0]['Request_Status__c']} | ticket={rs[0]['External_Key__c']} | status={rs[0]['External_Status__c']} | attempts={rs[0]['Attempts__c']} | error={(rs[0]['Last_Error_Short__c'] or '')[:90]}\")")
  echo "  +$(( $(date +%s)-T0 ))s  $R"
  case "$R" in *"| Created |"*|*"Failed - Terminal"*) break;; esac; sleep 5
done
echo "--- Opportunity ---"
sfq "SELECT Name, StageName, JIRA_SETUP_Issue__c, JIRA_SETUP_Status__c, JIRA_SETUP_Status_Updated__c, JIRA_Error_Message__c FROM Opportunity WHERE Id='$OPP'" | python3 -c "
import sys,json; r=json.load(sys.stdin)['result']['records'][0]
print(f\"  {r['Name']} | {r['StageName']} | key={r['JIRA_SETUP_Issue__c']} | status={r['JIRA_SETUP_Status__c']} | updated={r['JIRA_SETUP_Status_Updated__c']} | error={r['JIRA_Error_Message__c']}\")"
KEY=$(sfq "SELECT JIRA_SETUP_Issue__c FROM Opportunity WHERE Id='$OPP'" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['records'][0]['JIRA_SETUP_Issue__c'] or '')")
[ -n "$KEY" ] && { echo "KEY=$KEY" >> "$(dirname "$0")/.last-demo.env"; echo "--- Jira ticket via jira-sys-api ---"; curl -s --max-time 60 "http://localhost:8082/api/v1/issues/$KEY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"  {d['key']} | {d['summary']} | {d['status']['name']} | {d['url']}\")"; }
