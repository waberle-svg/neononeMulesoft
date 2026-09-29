#!/bin/zsh
# Step 2 — switch a Salesforce publisher Flow ON (only while the Mule apps are running, locally or on CloudHub).
#   demo/02-activate-publisher-flow.sh                 -> Opportunity_Publish_Integration_Request   (Scenario 1, provisioning)   [default]
#   demo/02-activate-publisher-flow.sh deactivation    -> Opportunity_Publish_Deactivation_Request  (Scenario 2, cancellation)
#   demo/02-activate-publisher-flow.sh all             -> both
# The Scenario 2 Flow must already exist in the org (manifest neon-jira-integration-scenario2.package.xml deployed).
# Switch OFF again with demo/06-stop.sh — the Dev sandbox is shared and every real transition would become a ticket.
source "$(dirname "$0")/demo-env.sh"
cd "$SFDX"
case "${1:-provisioning}" in
  provisioning) FLOWS=(Opportunity_Publish_Integration_Request);;
  deactivation) FLOWS=(Opportunity_Publish_Deactivation_Request);;
  all)          FLOWS=(Opportunity_Publish_Integration_Request Opportunity_Publish_Deactivation_Request);;
  *) echo "usage: $0 [provisioning|deactivation|all]"; exit 1;;
esac
for FLOW in $FLOWS; do
  F=force-app/main/default/flows/$FLOW.flow-meta.xml
  sed -i '' 's#<status>Draft</status>#<status>Active</status>#' "$F"
  sf project deploy start --test-level NoTestRun --metadata "Flow:$FLOW" -o "$ORG" --wait 10 2>&1 | grep -E "Status:|Error" | tail -2
  sed -i '' 's#<status>Active</status>#<status>Draft</status>#' "$F"     # keep the source file Draft
done
sf data query -o "$ORG" -q "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName IN ('Opportunity_Publish_Integration_Request','Opportunity_Publish_Deactivation_Request','Integration_Transaction_Apply_Jira_Updates')" 2>/dev/null | grep "│" | tail -3
