package dev.abdullah.vaultkey.fill

import org.json.JSONObject

/** A [FieldNode] read from a form fixture (the format `FormDump` writes). */
class JsonFieldNode(private val json: JSONObject) : FieldNode<JsonFieldNode> {
    override val idEntry: String? = string("id")
    override val hint: String? = string("hint")
    override val autofillHints: List<String> =
        json.optJSONArray("hints")?.let { a -> List(a.length()) { a.getString(it) } }.orEmpty()
    override val inputAttributes: Map<String, String> =
        json.optJSONObject("input")?.let { o -> o.keys().asSequence().associateWith { o.getString(it) } }.orEmpty()
    override val inputType: Int = json.optInt("inputType", 0)
    override val isTextField: Boolean = json.optBoolean("text", false)
    override val webDomain: String? = string("domain")
    override val children: List<JsonFieldNode> =
        json.optJSONArray("children")?.let { a -> List(a.length()) { JsonFieldNode(a.getJSONObject(it)) } }.orEmpty()

    /** How a test names this field: its HTML name or id, else its view id. */
    val label: String get() = inputAttributes["name"] ?: inputAttributes["id"] ?: idEntry ?: "?"

    private fun string(key: String): String? = if (json.has(key)) json.getString(key) else null

    companion object {
        fun fixture(name: String): List<JsonFieldNode> {
            val text = JsonFieldNode::class.java.getResource("/forms/$name.json")!!.readText()
            val roots = JSONObject(text).getJSONArray("roots")
            return List(roots.length()) { JsonFieldNode(roots.getJSONObject(it)) }
        }
    }
}
