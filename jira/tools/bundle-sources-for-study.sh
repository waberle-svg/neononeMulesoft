#!/bin/zsh
# Bundles the readable source of the three Mule apps into ONE text file you can paste into an LLM for study.
# Excludes everything secret or binary: secure-*.yaml, *.jks/*.p12/*.key, .env files, target/, coverage reports.
# Usage:  zsh tools/bundle-sources-for-study.sh            -> writes ~/Desktop/neon-mule-sources-<date>.txt
set -e
ROOT="${ROOT:-$HOME/Desktop/Neonone Mulesoft Project}"
OUT="${1:-$HOME/Desktop/neon-mule-sources-$(date +%Y%m%d).txt}"
: > "$OUT"
for APP in jira-sys-api salesforce-sys-api provisioning-prc-api; do
  echo "################################################################" >> "$OUT"
  echo "# PROJECT: $APP" >> "$OUT"
  echo "################################################################" >> "$OUT"
  echo "# Folder tree (secrets and build output omitted):" >> "$OUT"
  (cd "$ROOT/$APP" && find . -type f \
      ! -path "./target/*" ! -path "*/.mule/*" ! -path "./.tooling-project/*" ! -name ".DS_Store" \
      ! -name "secure-*.yaml" ! -name "*.jks" ! -name "*.p12" ! -name "*.key" ! -name "*.env" \
      | sort | sed 's|^\./|  |') >> "$OUT"
  echo >> "$OUT"
  (cd "$ROOT/$APP" && find . -type f \( -name "*.xml" -o -name "*.dwl" -o -name "*.raml" -o -name "*.yaml" -o -name "*.json" -o -name ".gitignore" \) \
      ! -path "./target/*" ! -path "*/.mule/*" ! -path "./.tooling-project/*" \
      ! -name "secure-*.yaml" ! -path "*/embedded-dw_*" \
      | sort) | while read -r F; do
    echo "=================================================================" >> "$OUT"
    echo "=== $APP/${F#./}" >> "$OUT"
    echo "=================================================================" >> "$OUT"
    cat "$ROOT/$APP/$F" >> "$OUT"
    echo >> "$OUT"
  done
done
# Secret files: names and key structure only, values masked
echo "################################################################" >> "$OUT"
echo "# SECRET FILES (structure only, values masked)" >> "$OUT"
echo "################################################################" >> "$OUT"
for APP in jira-sys-api salesforce-sys-api provisioning-prc-api; do
  for F in "$ROOT/$APP/src/main/resources/config/secure-dev.yaml" "$ROOT/$APP/src/test/resources/config/secure-test.yaml"; do
    [ -f "$F" ] || continue
    echo "=== $APP/${F#$ROOT/$APP/}" >> "$OUT"
    sed -E 's/:[[:space:]]*"[^"]*"/: "<masked>"/' "$F" >> "$OUT"
    echo >> "$OUT"
  done
done
echo "=== .mule-local.env (names only)" >> "$OUT"
sed -E 's/=.*/=<masked>/' "$ROOT/.mule-local.env" >> "$OUT"
echo >> "$OUT"
echo "=== ~/.m2/settings.xml (structure, values masked)" >> "$OUT"
sed -E 's/(<password>|<anypoint\.client\.[a-z]+>)[^<]*/\1<masked>/g' "$HOME/.m2/settings.xml" >> "$OUT"
# Safety check: no ciphertext, no plain secrets, no tokens
if grep -qE '!\[[A-Za-z0-9+/=]{20,}\]|ATATT3x|~\?~[A-Za-z0-9]{10,}' "$OUT"; then
  echo "SAFETY CHECK FAILED: secret-looking content found in $OUT — not safe to paste" >&2; exit 2
fi
echo "Bundle written: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes, $(grep -c '^=== ' "$OUT") files). Safety check passed."
