%dw 2.0
/**
 * Registry.dwl — the one place that knows how Integration_Transaction__c maps to the canonical
 * IntegrationRequest shape (and back). Imported by every registry flow so reads and writes cannot drift.
 *
 *   import * from modules::Registry
 */

// Fields read from Salesforce for every registry query (keep in sync with toCanonical below)
var soqlFields = "Id, Name, Target_System__c, Request_Type__c, Request_Status__c, Opportunity__c, Account__c, " ++
    "Source_Business_Key__c, Attempts__c, Last_Error__c, Last_Error_Short__c, Error_Category__c, Mule_Correlation_Id__c, " ++
    "External_Key__c, External_Id__c, External_URL__c, External_Container__c, External_Type__c, " ++
    "External_Status__c, External_Status_Id__c, External_Status_Category__c, Status_Changed_At__c, Last_Synced_At__c, " ++
    "CreatedDate, LastModifiedDate"

// Canonical (flattened, "external.x" for the nested group) -> Salesforce API name. Only these keys are writable.
var fieldMap = {
    requestStatus:              "Request_Status__c",
    attempts:                   "Attempts__c",
    lastError:                  "Last_Error__c",
    errorCategory:              "Error_Category__c",
    muleCorrelationId:          "Mule_Correlation_Id__c",
    requestPayload:             "Request_Payload__c",
    responsePayload:            "Response_Payload__c",
    "external.key":             "External_Key__c",
    "external.id":              "External_Id__c",
    "external.url":             "External_URL__c",
    "external.container":       "External_Container__c",
    "external.type":            "External_Type__c",
    "external.status":          "External_Status__c",
    "external.statusId":        "External_Status_Id__c",
    "external.statusCategory":  "External_Status_Category__c",
    "external.statusChangedAt": "Status_Changed_At__c",
    "external.lastSyncedAt":    "Last_Synced_At__c"
}

// Long text areas are 32,768 chars in Salesforce; anything longer would be rejected (STRING_TOO_LONG)
var longTextFields = ["Last_Error__c", "Request_Payload__c", "Response_Payload__c"]
var longTextMax = 32768

// DateTime fields: the connector needs typed DateTime values, not ISO strings
// (found live 19 Sep 2026: "Last Synced At: value not of required type", ERR-0011)
var dateTimeFields = ["Status_Changed_At__c", "Last_Synced_At__c"]
var numberFields   = ["Attempts__c"]

fun coerce(sfName: String, v) =
    if (v == null) null
    else if (dateTimeFields contains sfName) (v as DateTime)
    else if (numberFields contains sfName) (v as Number)
    else if (longTextFields contains sfName) clamp(v, longTextMax)
    else v

fun clamp(value, max: Number) =
    if (value == null) null
    else if (sizeOf(value as String) > max) (value as String)[0 to max - 1]
    else value

/** Salesforce row (Map from salesforce:query) -> canonical IntegrationRequest */
fun toCanonical(r) = {
    id:                r.Id,
    name:              r.Name,
    targetSystem:      r.Target_System__c,
    requestType:       r.Request_Type__c,
    requestStatus:     r.Request_Status__c,
    opportunityId:     r.Opportunity__c,
    accountId:         r.Account__c,
    sourceBusinessKey: r.Source_Business_Key__c,
    attempts:          if (r.Attempts__c == null) null else (r.Attempts__c as Number),
    lastError:         r.Last_Error__c,
    lastErrorShort:    r.Last_Error_Short__c,
    errorCategory:     r.Error_Category__c,
    muleCorrelationId: r.Mule_Correlation_Id__c,
    external: {
        key:             r.External_Key__c,
        id:              r.External_Id__c,
        url:             r.External_URL__c,
        container:       r.External_Container__c,
        "type":          r.External_Type__c,
        status:          r.External_Status__c,
        statusId:        r.External_Status_Id__c,
        statusCategory:  r.External_Status_Category__c,
        statusChangedAt: r.Status_Changed_At__c,
        lastSyncedAt:    r.Last_Synced_At__c
    },
    createdDate:       r.CreatedDate,
    lastModifiedDate:  r.LastModifiedDate
}

/**
 * Canonical update body -> Salesforce record Map.
 *  - unknown keys are ignored (the API contract is the whitelist above)
 *  - keys sent with an explicit null are cleared in Salesforce via fieldsToNull (the connector ignores plain nulls)
 *  - long text values are clamped to the field length
 *  - `base` carries Id (update) or the identifying/default fields (create)
 */
fun toRecord(body, base) = do {
    var flat   = (body - "external") ++ ((body.external default {}) mapObject ((v, k) -> { ("external." ++ (k as String)): v }))
    var known  = flat filterObject ((v, k) -> fieldMap[(k as String)] != null)
    var values = (known filterObject ((v, k) -> v != null))
                    mapObject ((v, k) -> do {
                        var sfName = fieldMap[(k as String)] as String
                        ---
                        { (sfName): coerce(sfName, v) }
                    })
    var toNull = (known filterObject ((v, k) -> v == null)) pluck ((v, k) -> fieldMap[(k as String)] as String)
    // Last_Error_Short__c (Text 255) always mirrors Last_Error__c: Flow formulas cannot read Long Text Areas (ERR-0013),
    // so the registry Flow copies the short form to Opportunity.JIRA_Error_Message__c. Cleared together with lastError.
    var shortError = if (known.lastError != null) { Last_Error_Short__c: clamp(known.lastError, 255) } else {}
    var toNullAll  = toNull ++ (if ((known filterObject ((v, k) -> v == null)).lastError? ) ["Last_Error_Short__c"] else [])
    ---
    base ++ values ++ shortError ++ (if (isEmpty(toNullAll)) {} else { fieldsToNull: toNullAll })
}

/**
 * First result item of salesforce:update / create / upsert. The connector returns either a plain array of
 * { id, success, errors } or (Salesforce connector 10.x/11.x) an object { id, items: [ { id, success?, exception?, errors? } ] }
 * — seen live on 19 Sep 2026 (ERR-0011). Accept both.
 */
fun firstResult(payload) =
    if (payload == null) null
    else if (payload is Array) payload[0]
    else if (payload.items is Array) payload.items[0]
    else payload

/** True when Salesforce accepted the write, whichever result shape came back */
fun writeSucceeded(result) =
    result != null and (
        result.success == true
        or (result.success == null and result.exception == null and isEmpty(result.errors default []) and result.id != null)
    )

/** Result item -> human-readable error text (null when success) */
fun writeError(result) =
    if (result == null) "Salesforce returned no result"
    else if (writeSucceeded(result)) null
    else if (result.exception != null)
        ((result.exception.statusCode default result.exception.'type' default "ERROR") as String) ++ ": "
            ++ ((result.exception.localizedMessage default result.exception.message default "") as String)
    else ((result.errors default []) map ((e) -> ((e.statusCode default "ERROR") ++ ": " ++ (e.message default "") ++
            (if (isEmpty(e.fields default [])) "" else " [" ++ ((e.fields default []) joinBy ", ") ++ "]"))) joinBy "; ")
