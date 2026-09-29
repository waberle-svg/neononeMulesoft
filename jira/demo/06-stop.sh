#!/bin/zsh
# Step 6 — switch BOTH publisher Flows OFF and stop a local Mule if one runs. Always run this at the end of a demo or test.
# (Deploying the FlowDefinition with activeVersionNumber 0 deactivates the Flow; a Flow that is not in the org yet just reports an error and is skipped.)
source "$(dirname "$0")/demo-env.sh"
cd "$SFDX"
for FLOW in Opportunity_Publish_Integration_Request Opportunity_Publish_Deactivation_Request; do
  sf project deploy start --test-level NoTestRun --metadata "FlowDefinition:$FLOW" -o "$ORG" --wait 10 2>&1 | grep -E "Status:|Error" | tail -1
done
sf data query -o "$ORG" -q "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName IN ('Opportunity_Publish_Integration_Request','Opportunity_Publish_Deactivation_Request')" 2>/dev/null | grep "│" | tail -2
if pgrep -f mule-enterprise-standalone >/dev/null; then "$RT/bin/mule" stop | grep -E "Stopped|not running"; else echo "no local Mule running (the CloudHub apps are unaffected)"; fi
echo "mule processes left: $(pgrep -f mule-enterprise-standalone | wc -l | tr -d ' ')"
