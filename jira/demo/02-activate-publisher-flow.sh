#!/bin/zsh
# Step 2 — switch the Salesforce publisher Flow ON (only while Mule is running).
source "$(dirname "$0")/demo-env.sh"
cd "$SFDX"
F=force-app/main/default/flows/Opportunity_Publish_Integration_Request.flow-meta.xml
sed -i '' 's#<status>Draft</status>#<status>Active</status>#' "$F"
sf project deploy start --test-level NoTestRun --metadata "Flow:Opportunity_Publish_Integration_Request" -o "$ORG" --wait 10 2>&1 | grep -E "Status:|Error" | tail -2
sed -i '' 's#<status>Active</status>#<status>Draft</status>#' "$F"     # keep the source file Draft
sf data query -o "$ORG" -q "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName IN ('Opportunity_Publish_Integration_Request','Integration_Transaction_Apply_Jira_Updates')" 2>/dev/null | grep "│" | tail -2
