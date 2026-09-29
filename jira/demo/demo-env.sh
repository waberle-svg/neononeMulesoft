#!/bin/zsh
# Shared settings for the demo scripts. Source this first:  source demo/demo-env.sh
# Repo root = the folder above this script (works when sourced from zsh); override with ROOT=/path if needed
export ROOT="${ROOT:-${${(%):-%x}:A:h:h}}"
export SFDX="$ROOT/salesforce"                 # the integration's own Salesforce metadata (source of truth since 29 Sep 2026); the full org retrieve stays in ~/Desktop/NEONONE SF
export RT="$HOME/AnypointCodeBuilder/runtime/mule-enterprise-standalone-4.12.3"
export DEPS="$HOME/.vscode/extensions/salesforce.mule-dx-dependencies-1.7.1-darwin-arm64/build/deps"
export JAVA_HOME="$DEPS/jdk-17.0.13+11/Contents/Home"
export ORG="neon-dev"                       # Salesforce CLI alias of the Dev sandbox
export ORG_ID="00DSu000008AXB0MAO"
set -a; source "$ROOT/.mule-local.env"; set +a   # MULE_SECURE_KEY (never printed)
sfq() { sf data query -o "$ORG" --json -q "$1" 2>/dev/null | sed '/^ ›/d'; }
