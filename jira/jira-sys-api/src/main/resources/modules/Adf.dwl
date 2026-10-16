%dw 2.0
/**
 * Adf.dwl — Atlassian Document Format for the texts this API sends to Jira Cloud (REST v3 needs ADF for
 * `description` and for every multi-line custom field).
 *
 *   toAdf(text)     the canonical description -> ADF document, rendering a small markup (documented in the RAML):
 *                     blank line                     new paragraph
 *                     single newline                 line break inside the paragraph (hardBreak)
 *                     "- " at the start of a line    bullet; a block whose lines are all bullets becomes one bullet list
 *                     **text**                       bold
 *                     __text__                       underline
 *                     a line that is only an e-mail  mailto link
 *                   Modelled on how the setup team writes tickets by hand (SETUP-11083).
 *   adfLines(text)  one plain paragraph per non-blank line (Additional Users: one user per line).
 *
 *   import * from modules::Adf
 */

var emailRe = /^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/

fun textNode(t: String, marks: Array) =
    if (isEmpty(marks)) { "type": "text", text: t } else { "type": "text", text: t, marks: marks }

/** inline markup of one line: **bold** and __underline__ segments; everything else plain text */
fun inline(line: String): Array =
    (line scan /\*\*[^*]+\*\*|__[^_]+__|[^*_]+|[*_]/) map ((m) -> do {
        var t = m[0]
        ---
        if ((t startsWith "**") and (t endsWith "**") and sizeOf(t) > 4) textNode(t[2 to -3], [{ "type": "strong" }])
        else if ((t startsWith "__") and (t endsWith "__") and sizeOf(t) > 4) textNode(t[2 to -3], [{ "type": "underline" }])
        else textNode(t, [])
    })

fun lineNodes(line: String): Array =
    if (line matches emailRe) [textNode(line, [{ "type": "link", attrs: { href: "mailto:" ++ line } }])]
    else inline(line)

fun hardBreak() = { "type": "hardBreak" }

/** one paragraph; lines separated by hard breaks */
fun paragraphOf(lines: Array) =
    { "type": "paragraph", content: flatten(lines map ((l, i) -> (if (i == 0) [] else [hardBreak()]) ++ lineNodes(l))) }

fun isBullet(l: String): Boolean = (l startsWith "- ") and sizeOf(l) > 2

fun bulletListOf(lines: Array) =
    { "type": "bulletList",
      content: lines map ((l) -> { "type": "listItem", content: [ { "type": "paragraph", content: lineNodes(trim(l[2 to -1])) } ] }) }

fun block(lines: Array) =
    if (isEmpty(lines filter ((l) -> !isBullet(l)))) bulletListOf(lines) else paragraphOf(lines)

/** canonical description (markup above) -> ADF document; never empty (Jira rejects an empty document) */
fun toAdf(text) = do {
    var blocks = (((text default "") as String) splitBy /\n[ \t]*\n+/)
                    map ((b) -> (b splitBy "\n") map trim($) filter ((l) -> !isEmpty(l)))
                    filter ((b) -> !isEmpty(b))
    ---
    { "type": "doc", version: 1, content: if (isEmpty(blocks)) [paragraphOf([" "])] else (blocks map block($)) }
}

/** one plain paragraph per non-blank line, no markup (Additional Users) */
fun adfLines(text) = do {
    var lines = (((text default "") as String) splitBy "\n") map trim($) filter ((l) -> !isEmpty(l))
    ---
    { "type": "doc", version: 1,
      content: if (isEmpty(lines)) [paragraphOf([" "])] else (lines map ((l) -> { "type": "paragraph", content: [textNode(l, [])] })) }
}
