#!/bin/zsh
# Step 3 — create a demo Account + Opportunity and move it to Closed Won so the loop fires.
# Passes every active validation rule for a System Administrator (Next_Steps__c is the one that applies).
source "$(dirname "$0")/demo-env.sh"
cd "$SFDX"
TS=$(date +%d%b%H%M)                                  # e.g. 20Sep0105 — keeps names/instance unique
NAME="${1:-Demo Org $TS}"                             # optional: ./03-create-opportunity.sh "Acme Nonprofit"
INSTANCE="demo$(date +%d%H%M%S)"                      # letters+digits only (validation rule No_Spaces_Or_Special_Characters)
echo "Account name: $NAME | instance: $INSTANCE"
ACC=$(sf data create record -o "$ORG" -s Account -v "Name='$NAME' IsTestAccount__c=false" --json 2>/dev/null | sed '/^ ›/d' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['id'] if d.get('status')==0 else 'ERROR '+d.get('message',''))")
echo "Account:     $ACC"; case "$ACC" in ERROR*) exit 1;; esac
OPP=$(sf data create record -o "$ORG" -s Opportunity -v "Name='$NAME - CRM' AccountId='$ACC' StageName='Stage 1 - Discovery' CloseDate=$(date -v+10d +%Y-%m-%d) Type='New' ProductionInstanceName__c='$INSTANCE' Project_Requirement_Met__c=true Next_Steps__c='Demo of the MuleSoft Jira integration' Description='Demo opportunity for the Salesforce to Jira MuleSoft integration.'" --json 2>/dev/null | sed '/^ ›/d' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['id'] if d.get('status')==0 else 'ERROR '+d.get('message',''))")
echo "Opportunity: $OPP"; case "$OPP" in ERROR*) exit 1;; esac
echo "ACC=$ACC
OPP=$OPP" > "$(dirname "$0")/.last-demo.env"
echo "--- moving to Closed Won (this is the trigger) ---"
sf data update record -o "$ORG" -s Opportunity -i "$OPP" -v "StageName='Closed Won'" --json 2>/dev/null | sed '/^ ›/d' | python3 -c "import sys,json; d=json.load(sys.stdin); print('Closed Won:', 'OK' if d.get('status')==0 else 'ERROR '+d.get('message',''))"
echo "Now run 04-watch.sh"
