#!/bin/zsh
# check-uat-prerequisites.sh — READ-ONLY. Proves that every field owned by the Salesforce team that our integration
# depends on exists in the target org BEFORE our packages are deployed. The list is derived from the permission set
# Jira_Integration_Access (it grants FLS on every field Mule reads or the Flows write): if one is missing in the target
# org, package 1 fails on the PermissionSet component, and Mule's queries would fail at runtime.
# Existence is checked through the Tooling API (CustomField), which does NOT depend on the running user's field-level
# security — a describe call would hide fields the user cannot see and report them as missing.
#   usage: scripts/check-uat-prerequisites.sh <org alias>        e.g. scripts/check-uat-prerequisites.sh neon-uat
#   exit 0 = everything present · 1 = something missing (listed) · 2 = cannot read an object (alias/access)
set -u
ORG="${1:?org alias required, e.g. neon-uat}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PS="$HERE/force-app/main/default/permissionsets/Jira_Integration_Access.permissionset-meta.xml"
# Fields in the permission set that are NOT ours (ours = our two objects + the three standard-object formula fields we deploy;
# the two Opportunity status fields were retired)
OURS='^(Integration_Transaction__c\.|Integration_Request__e\.|OrderItem\.Integration_Product_Line__c$|OrderItem\.Integration_Sync_JIRA__c$|OpportunityLineItem\.Integration_Product_Line__c$)'
required=$(grep -o '<field>[A-Za-z0-9_]*\.[A-Za-z0-9_]*</field>' "$PS" | sed 's/<[^>]*>//g' | grep -v -E "$OURS" | sort -u)
objects=$(echo "$required" | cut -d. -f1 | sort -u)
missing=0; checked=0
for obj in ${(f)objects}; do
  # Tooling API: every custom field of the object, regardless of field-level security. Standard objects are addressed
  # by name; a custom object would need its DurableId (none of the team's fields live on custom objects today).
  fields=$(sf data query --target-org "$ORG" --use-tooling-api --json \
             -q "SELECT DeveloperName FROM CustomField WHERE TableEnumOrId='$obj'" 2>/dev/null \
           | jq -r '.result.records[]?.DeveloperName | . + "__c"')
  if [ -z "$fields" ]; then echo "ERROR: cannot read custom fields of $obj in $ORG (object missing, wrong alias, or no access)"; exit 2; fi
  for spec in ${(f)"$(echo "$required" | grep "^$obj\.")"}; do
    f="${spec#*.}"; checked=$((checked+1))
    if ! echo "$fields" | grep -qx "$f"; then echo "MISSING  $spec"; missing=$((missing+1)); fi
  done
done
echo "checked $checked team-owned fields across $(echo "$objects" | wc -l | tr -d ' ') objects in $ORG: $missing missing"
[ "$missing" -eq 0 ]
