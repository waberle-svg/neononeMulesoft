#!/bin/zsh
# Step 4 — watch the loop for the Opportunity in .last-demo.env (or the one given as $1):
#   every registry row of the Opportunity (SETUP and, since Scenario 2, one DEACTIVATION row per product line)
#   → the Opportunity's Jira fields (System Setup key/status and the three cancellation key/error pairs)
#   → the Jira ticket(s) through jira-sys-api (local by default; JIRA_SYS_URL=https://<host> for the CloudHub app, headers added when INTER_APP_SECRET is set)
source "$(dirname "$0")/demo-env.sh"; [ -f "$(dirname "$0")/.last-demo.env" ] && source "$(dirname "$0")/.last-demo.env"
OPP="${1:-$OPP}"; [ -z "$OPP" ] && { echo "usage: $0 <OpportunityId>   (or run 03 first)"; exit 1; }
cd "$SFDX"; T0=$(date +%s)
for i in $(seq 1 24); do
  R=$(sfq "SELECT Name, Request_Type__c, Product_Line__c, Request_Status__c, External_Key__c, External_Status__c, Attempts__c, Last_Error_Short__c FROM Integration_Transaction__c WHERE Opportunity__c='$OPP' ORDER BY CreatedDate" | python3 -c "
import sys,json; rs=json.load(sys.stdin)['result']['records']
if not rs: print('no registry row yet'); sys.exit(0)
final = all(r['Request_Status__c'] in ('Created','Failed - Terminal','Cancelled') for r in rs)
for r in rs:
    print(f\"{r['Name']} | {r['Request_Type__c']} {r['Product_Line__c'] or ''} | {r['Request_Status__c']} | ticket={r['External_Key__c']} | status={r['External_Status__c']} | attempts={r['Attempts__c']} | error={(r['Last_Error_Short__c'] or '')[:90]}\")
print('ALL_FINAL' if final else 'PENDING')")
  echo "  +$(( $(date +%s)-T0 ))s"; echo "$R" | grep -v "ALL_FINAL\|PENDING" | sed 's/^/    /'
  case "$R" in *ALL_FINAL*) break;; esac; sleep 5
done
echo "--- Opportunity ---"
sfq "SELECT Name, StageName, Risk_Stage__c, JIRA_SETUP_Issue__c, JIRA_SETUP_Status__c, JIRA_Error_Message__c, Neon_CRM_Cancellation_JIRA__c, Neon_CRM_Cancellation_Error__c, Fundraise_Cancellation_JIRA__c, Fundraise_Cancellation_Error__c, Arts_People_Cancellation_JIRA__c, Arts_People_Cancellation_Error__c FROM Opportunity WHERE Id='$OPP'" | python3 -c "
import sys,json; r=json.load(sys.stdin)['result']['records'][0]
print(f\"  {r['Name']} | {r['StageName']} | risk={r['Risk_Stage__c']}\")
print(f\"  System Setup : key={r['JIRA_SETUP_Issue__c']} | status={r['JIRA_SETUP_Status__c']} | error={r['JIRA_Error_Message__c']}\")
for line,k,e in (('Neon CRM','Neon_CRM_Cancellation_JIRA__c','Neon_CRM_Cancellation_Error__c'),('Neon Fundraise','Fundraise_Cancellation_JIRA__c','Fundraise_Cancellation_Error__c'),('Arts People','Arts_People_Cancellation_JIRA__c','Arts_People_Cancellation_Error__c')):
    if r[k] or r[e]: print(f\"  Deactivation {line}: key={r[k]} | error={(r[e] or '')[:120]}\")"
KEYS=$(sfq "SELECT External_Key__c FROM Integration_Transaction__c WHERE Opportunity__c='$OPP' AND External_Key__c != null" | python3 -c "import sys,json; print(' '.join(r['External_Key__c'] for r in json.load(sys.stdin)['result']['records']))")
if [ -n "$KEYS" ]; then
  echo "KEY=${KEYS##* }" >> "$(dirname "$0")/.last-demo.env"
  echo "--- Jira ticket(s) via jira-sys-api (${JIRA_SYS_URL:-http://localhost:8082}) ---"
  for KEY in ${=KEYS}; do
    curl -s --max-time 60 ${INTER_APP_SECRET:+-H "X-Client-Id: demo" -H "X-Client-Secret: $INTER_APP_SECRET"} "${JIRA_SYS_URL:-http://localhost:8082}/api/v1/issues/$KEY" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"  {d.get('key')} | {d.get('issueType')} | {d.get('summary')} | {(d.get('status') or {}).get('name')} | {d.get('url')}\")" 2>/dev/null || echo "  $KEY: jira-sys-api not reachable at ${JIRA_SYS_URL:-http://localhost:8082}"
  done
fi
