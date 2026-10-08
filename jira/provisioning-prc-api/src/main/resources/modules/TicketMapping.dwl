%dw 2.0
import try from dw::Runtime
import firstWith, some from dw::core::Arrays
/**
 * TicketMapping.dwl — a tiny mapping engine: turns a mapping YAML (mapping/provisioning-ticket.yaml,
 * mapping/deactivation-ticket.yaml) plus a context { opp, req, registry, line?, env, sfUrl } into the canonical
 * IssueCreateRequest expected by jira-sys-api. A `source` may resolve to an array (e.g. labels); it is passed through.
 *
 *   import * from modules::TicketMapping
 *   buildTicket(readUrl("classpath://mapping/provisioning-ticket.yaml", "application/yaml"), ctx)
 *
 * A leaf spec has one of: source | template | rule | value, plus optional default and maxLength.
 * Anything else is a group and is built recursively, so the YAML shape is the ticket shape.
 */

var specKeys = ["source", "template", "rule", "value"]

fun isSpec(node) = (node is Object) and !isEmpty((keysOf(node) map ($ as String)) filter ((k) -> specKeys contains k))

/** "a.b.c" against a nested object; null as soon as a segment is missing */
fun resolve(ctx, path: String) =
    (path splitBy ".") reduce ((seg, acc = ctx) -> if (acc == null) null else acc[seg])

/** replaces every {path} token; a missing value becomes "" */
fun fillTemplate(template: String, ctx) =
    template replace /\{([A-Za-z0-9_.]+)\}/ with ((m) -> (resolve(ctx, m[1]) default "") as String)

/** named rules: business logic that is more than a copy (kept here, referenced from the YAML by name) */
fun applyRule(rule: String, ctx) =
    rule match {
        // Q21 candidate: the Web Template Copy roll-up on the Opportunity says whether the product was bought
        case "webTemplateCopy" ->
            if (((ctx.opp.includesWebTemplateCopy default 0) as Number) > 0) "COPY_NOW" else "NOT_PURCHASED"
        // Q16 candidates: NeonCRM_Modules__c ("A|B|C"), else the product names inside ProductRollup__c ("CODE::Name::Desc|…")
        case "modules" -> do {
            var fromModules = trim((ctx.opp.neonCrmModules default "") as String)
            var fromRollup  = (((ctx.opp.productRollup default "") as String) splitBy "|")
                                map ((item) -> trim(((item splitBy "::")[1]) default item))
                                filter ((name) -> !isEmpty(name))
                                joinBy ", "
            ---
            if (!isEmpty(fromModules)) fromModules replace "|" with ", "
            else if (!isEmpty(fromRollup)) fromRollup
            else null
        }
        // ---- Scenario 1, Order model (requirements v3) ----
        // Modules is NOT a rule any more (Swati, 7 Oct 2026): the ticket carries Order.NeonCRM_Modules__c exactly as Salesforce
        // built it, or the literal "NA" when that field is blank — a plain source + default leaf in setup-order-ticket.yaml.
        // Implementation Type: first matching rule over Opportunity.ProductRollup__c (case-insensitive substring),
        // table in the mapping YAML (rules.implementationType), else rules.implementationTypeDefault
        case "implementationType" -> do {
            var rollup = lower((ctx.opp.productRollup default "") as String)
            var rules  = (ctx.rules.implementationType default []) as Array
            var hit    = rules firstWith ((r) -> ((r.contains default []) map lower($ as String)) some ((needle) -> rollup contains needle))
            ---
            if (hit != null) hit.value else ctx.rules.implementationTypeDefault
        }
        // "Additional User (at time of setup)" Contacts of the Account: First Last <email>, ONE PER LINE —
        // the Jira field is a multi-line text field and jira-sys-api turns each line into an ADF paragraph (ERR-0024)
        case "additionalUsers" -> do {
            var users = (ctx.order.additionalUsers default []) map ((u) ->
                            trim((u.name default "") as String) ++ (if (u.email == null) "" else " <" ++ (u.email as String) ++ ">"))
                        filter ((s) -> !isEmpty(trim(s)))
            ---
            if (isEmpty(users)) null else (users joinBy "\n")
        }
        // Contact blocks of the description ("<Header>\n<name>\n<email>"); header hidden when the contact is blank
        // (document: "only if it's not blank otherwise hide header also" — applied to all three contact blocks)
        case "primaryContactBlock"   -> contactBlock("Primary Contact",   ctx.opp.primaryContact)
        case "technicalContactBlock" -> contactBlock("Technical Contact", ctx.opp.technicalContact)
        case "partnerBlock"          -> contactBlock("Partner Contact",   ctx.opp.partnerContact)
        else -> null
    }

fun contactBlock(header: String, c) = do {
    var name  = trim((c.name default "") as String)
    var email = trim((c.email default "") as String)
    ---
    if (c == null or (isEmpty(name) and isEmpty(email))) null
    else header ++ "\n" ++ (if (isEmpty(name)) "" else name ++ "\n") ++ (if (isEmpty(email)) "" else email ++ "\n")
}

fun evalSpec(spec, ctx) = do {
    var raw =
        if (spec.value != null) spec.value
        else if (spec.template != null) fillTemplate(spec.template as String, ctx)
        else if (spec.rule != null) applyRule(spec.rule as String, ctx)
        else if (spec.source != null) resolve(ctx, spec.source as String)
        else null
    var nonBlank = if (raw is String and isEmpty(trim(raw))) null else raw
    var withDefault = nonBlank default spec."default"
    var maxLength = spec.maxLength
    ---
    if (withDefault == null) null
    else if (maxLength != null and withDefault is String and sizeOf(withDefault) > (maxLength as Number))
        (withDefault as String)[0 to (maxLength as Number) - 1]
    else withDefault
}

fun build(node, ctx) =
    if (isSpec(node)) evalSpec(node, ctx)
    else if (node is Object) node mapObject ((v, k) -> { (k): build(v, ctx) })
    else node

/** mapping = parsed YAML; returns the canonical IssueCreateRequest (nulls kept; jira-sys-api skips them) */
fun buildTicket(mapping, ctx) = build(mapping.fields, ctx)

/**
 * Failure classification for the orchestration: retryable or terminal, and the Error_Category__c picklist value.
 * Uses the downstream canonical error body when the HTTP connector attached one, else the error type.
 */
fun classify(err) = do {
    var errNs = err.errorType.namespace default ""
    var id    = err.errorType.identifier default ""
    // the downstream canonical error body, when the HTTP connector attached a parseable one
    var bodyAttempt = try(() -> err.errorMessage.payload)
    var body  = if (bodyAttempt.success and bodyAttempt.result is Object) bodyAttempt.result else null
    var statusAttempt = try(() -> err.errorMessage.attributes.statusCode)
    var status = if (statusAttempt.success) statusAttempt.result else null
    var bodyRetryable = body.retryable
    var byType =
        if (errNs == "HTTP") (
            if (["CONNECTIVITY", "TIMEOUT", "RETRY_EXHAUSTED", "TOO_MANY_REQUESTS", "INTERNAL_SERVER_ERROR", "BAD_GATEWAY", "SERVICE_UNAVAILABLE", "GATEWAY_TIMEOUT"] contains id) true
            else false)
        else if (errNs == "MULE" and (["EXPRESSION", "TRANSFORMATION"] contains id)) false
        else if (errNs == "APP") false
        else true
    var retryable = if (bodyRetryable is Boolean) bodyRetryable else byType
    var code = body.code default (errNs ++ ":" ++ id)
    // Our own data guards: the Salesforce record lacks what the ticket needs -> a data problem, category Mapping
    //   Scenario 2: MISSING_INSTANCE_ID, UNSUPPORTED_PRODUCT_LINE · Scenario 1 Order model: NO_SETUP_ITEMS
    var dataGuards = ["MISSING_INSTANCE_ID", "UNSUPPORTED_PRODUCT_LINE", "NO_SETUP_ITEMS"]
    var category =
        if (retryable) "Transient"
        else if ((["UNAUTHORIZED", "FORBIDDEN"] contains (body.code default "")) or (["UNAUTHORIZED", "FORBIDDEN"] contains id)) "Auth"
        else if ((body.code default "") == "VALIDATION" or id == "BAD_REQUEST" or (errNs == "MULE")) "Mapping"
        else if (errNs == "APP" and (dataGuards contains id)) "Mapping"
        else "Terminal"
    ---
    {
        retryable: retryable,
        category:  category,
        code:      code,
        status:    status,
        message:   (body.message default err.description default "Unexpected error") as String,
        detail:    body
    }
}

/** exponential backoff in seconds: base * 2^(attempt-1), capped */
fun backoffSeconds(attempt: Number, baseSeconds: Number, maxSeconds: Number) =
    min([ baseSeconds * pow(2, max([attempt - 1, 0])), maxSeconds ])
