# sf-to-rocketlane

MuleSoft app that creates a Rocketlane project whenever a `Project__c` record is created in Salesforce, then writes the Rocketlane project Id back to the Salesforce record.

## How it works

```
Replay channel listener  (/data/Project__ChangeEvent, ONLY_NEW)
└─ Choice
   ├─ When changeType == "CREATE"
   │   ├─ Request  GET /fields (single-choice)  → vars.rlSingleChoice
   │   ├─ Request  GET /fields (multi-choice)   → vars.rlMultiChoice
   │   └─ Query Project__c with its Account__r and Opportunity__r fields
   │         WHERE Id IN :ids AND Rocketlane_Id__c = null
   │       └─ For Each
   │           ├─ Set Variable  accountWebsite, sfId
   │           ├─ Transform     → Rocketlane JSON body (standard + custom fields)
   │           ├─ Request       POST /projects (Rocketlane_HTTP)
   │           ├─ Set Variable  rlCompanyId = customer.companyId
   │           ├─ Update        Project__c.Rocketlane_Id__c = projectId
   │           ├─ Choice        if the Account has a Website:
   │           │                PUT /companies/{companyId} { companyUrl }
   │           └─ Logger
   └─ Default (UPDATE events are ignored)
```

- Salesforce login: OAuth JWT Bearer through an External Client App and an API-only integration user.
- Rocketlane auth: `api-key` header, sent as a default header by `Rocketlane_HTTP`.
- Duplicates are prevented by the `Rocketlane_Id__c = null` filter. The write-back causes an UPDATE event, which the Choice ignores.
- Rocketlane custom fields are sent as `fields: [{ fieldId, fieldValue }]`. Choice fields are sent as Rocketlane option numbers, looked up by label at runtime from `GET /fields`, so option numbers never need to be configured.
- Empty Salesforce values, and choice values with no matching Rocketlane option, are left out.

## Prerequisites

- Anypoint Studio with Mule runtime 4.12 (Java 17).
- Salesforce: Change Data Capture enabled for `Project__c`, field `Rocketlane_Id__c`, integration user with the Rocketlane Integration permission set (read access to the mapped Project, Account and Opportunity fields), and an External Client App with JWT Bearer enabled.
- Rocketlane API key.

## Configuration

One config file per environment: `src/main/resources/config-${env}.yaml`. The app reads it through the Secure Properties config; `env` defaults to `dev` (global property) and is overridden at runtime with `-M-Denv=uat` or `-M-Denv=prod`.

| File | Environment |
|---|---|
| `config-dev.yaml` | Salesforce sandbox + Rocketlane Dev/UAT workspace |
| `config-uat.yaml` | to be added (same keys, UAT values) |
| `config-prod.yaml` | to be added (same keys, production values) |

Each file has the same keys:

- `rocketlane.*` and `salesforce.*`: connection settings. Secrets are encrypted (AES/CBC, random IVs) with the MuleSoft Secure Properties Tool.
- `rocketlaneFields.*`: Rocketlane custom field Ids (not secret). Dev and UAT share one Rocketlane workspace, so they share these Ids; production has its own.

All values are read as `${secure::...}` or `p('secure::...')`. Each environment uses its own master key.

Not in this repository, and never to be committed:

| Item | Where it goes |
|---|---|
| `rocketlane-sf.jks` (JWT private keystore) | Copy into `src/main/resources/` locally. Get it from the team's secure store. |
| Master key (`secure.key`) | Pass at runtime only (see below). Keep it in the password manager. |

## Run locally

1. Import the project into Anypoint Studio and add `rocketlane-sf.jks` to `src/main/resources/`.
2. **Run → Run Configurations… → Mule Applications**, and add this to the VM arguments:
   ```
   -M-Dsecure.key=<16-character master key>
   ```
   Add `-M-Denv=uat` or `-M-Denv=prod` for another environment (default: `dev`).
3. Run, wait for `DEPLOYED`, then create a Project in the Salesforce sandbox.

## Not built yet

- Project Notes and Additional Onboarding Notes (Rocketlane NOTE fields; API behaviour still to be checked).
- Legacy Database (on hold until the picklist mapping is confirmed).
- Two-way sync: Salesforce updates → Rocketlane, and Rocketlane changes → Salesforce (webhooks, needs a CloudHub deployment).
