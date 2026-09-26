#!/bin/zsh
# Step 6 — switch the publisher Flow OFF and stop Mule. Always run this at the end of a demo.
source "$(dirname "$0")/demo-env.sh"
cd "$SFDX"
sf project deploy start --test-level NoTestRun --metadata "FlowDefinition:Opportunity_Publish_Integration_Request" -o "$ORG" --wait 10 2>&1 | grep -E "Status:|Error" | tail -1
sf data query -o "$ORG" -q "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName='Opportunity_Publish_Integration_Request'" 2>/dev/null | grep "│" | tail -1
"$RT/bin/mule" stop | grep -E "Stopped|not running"
echo "mule processes left: $(pgrep -f mule-enterprise-standalone | wc -l | tr -d ' ')"
