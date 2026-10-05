# sf-to-rocketlane

MuleSoft app that creates a Rocketlane project whenever a `Project__c` record is created in Salesforce, then writes the Rocketlane project Id back to the Salesforce record.

## How it works

```
Replay channel listener  (/data/Project__ChangeEvent, ONLY_NEW)
└─ Choice
   ├─ When changeType == "CREATE"
   │   └─ Query Project__c (Id, Name, Account__r.Name, Rocketlane_Id__c)
   │         WHERE Id IN :ids AND Rocketlane_Id__c = null
   │       └─ For Each
   │           ├─ Set Variable  sfId = payload.Id
   │           ├─ Transform     → Rocketlane JSON body
   │           ├─ Request       POST /projects (Rocketlane_HTTP)
   │           ├─ Update        Project__c.Rocketlane_Id__c = projectId
   │           └─ Logger
   └─ Default (UPDATE events are ignored)
```

- Salesforce login: OAuth JWT Bearer through an External Client App and an API-only integration user.
- Rocketlane auth: `api-key` header, sent as a default header by `Rocketlane_HTTP`.
- Duplicates are prevented by the `Rocketlane_Id__c = null` filter. The write-back causes an UPDATE event, which the Choice ignores.

## Prerequisites

- Anypoint Studio with Mule runtime 4.12 (Java 17).
- Salesforce: Change Data Capture enabled for `Project__c`, field `Rocketlane_Id__c`, integration user with the Rocketlane Integration permission set, and an External Client App with JWT Bearer enabled.
- Rocketlane API key.

## Configuration

`src/main/resources/config-secure.yaml` holds all settings. Secrets are encrypted (AES/CBC, random IVs) with the MuleSoft Secure Properties Tool and are read as `${secure::...}`.

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
3. Run, wait for `DEPLOYED`, then create a Project in the Salesforce sandbox.

The current config points at the Salesforce **sandbox** (`test.salesforce.com`) and the Rocketlane sandbox key. Production needs its own External Client App, keystore, Rocketlane key, master key and `login.salesforce.com` endpoints.
