## What and why
<!-- One paragraph: the behaviour change and the reason (ticket / KB reference). -->

## Apps touched
- [ ] jira-sys-api
- [ ] salesforce-sys-api
- [ ] provisioning-prc-api
- [ ] demo / tools / docs only

## Checklist
- [ ] `mvn clean test` green in every app touched (paste the `Tests run:` lines below)
- [ ] No secret values, keystores, `.env` files or `target/` in the diff
- [ ] Config changes mirrored in `config-dev.yaml`, `config-uat.yaml`, `config-prod.yaml` (and `config-test.yaml` if tests read it)
- [ ] RAML updated if an endpoint or model changed
- [ ] Knowledge base updated (ADR / ERR / runbook) if a decision, error or operating step changed

## Test evidence
```
```

## Deployment notes
<!-- New Runtime Manager properties? Order of deployment? Rollback? "None" is a valid answer. -->
