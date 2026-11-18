package dev.abdullah.vaultkey.fill

import android.app.assist.AssistStructure
import android.os.Build
import android.view.View
import android.view.autofill.AutofillId
import androidx.annotation.RequiresApi

/**
 * The parts of a view the form parser reads. [ViewFieldNode] adapts the
 * platform's `AssistStructure.ViewNode`; tests adapt JSON fixtures, so the
 * parser runs on plain JVM.
 */
interface FieldNode<out N : FieldNode<N>> {
    val idEntry: String?
    val hint: String?
    val autofillHints: List<String>

    /** Lower-cased attribute names of an HTML `<input>`; empty for other nodes. */
    val inputAttributes: Map<String, String>
    val inputType: Int

    /** Whether the node can receive a text value (has an autofill id and type text). */
    val isTextField: Boolean
    val webDomain: String?
    val children: List<N>
}

@RequiresApi(Build.VERSION_CODES.O)
class ViewFieldNode(private val node: AssistStructure.ViewNode) : FieldNode<ViewFieldNode> {
    val autofillId: AutofillId? get() = node.autofillId

    /** What the user typed, once the page has been submitted. */
    val enteredText: String?
        get() = node.autofillValue?.takeIf { it.isText }?.textValue?.toString()

    override val idEntry: String? get() = node.idEntry
    override val hint: String? get() = node.hint
    override val autofillHints: List<String> get() = node.autofillHints?.toList().orEmpty()
    override val inputType: Int get() = node.inputType
    override val isTextField: Boolean
        get() = node.autofillId != null && node.autofillType == View.AUTOFILL_TYPE_TEXT
    override val webDomain: String? get() = node.webDomain

    override val inputAttributes: Map<String, String>
        get() {
            val info = node.htmlInfo ?: return emptyMap()
            if (!info.tag.equals("input", ignoreCase = true)) return emptyMap()
            val attrs = info.attributes ?: return emptyMap()
            val map = HashMap<String, String>(attrs.size)
            for (pair in attrs) {
                val name = pair.first ?: continue
                map[name.lowercase()] = pair.second.orEmpty()
            }
            return map
        }

    override val children: List<ViewFieldNode>
        get() = List(node.childCount) { ViewFieldNode(node.getChildAt(it)) }

    companion object {
        fun roots(structure: AssistStructure): List<ViewFieldNode> =
            (0 until structure.windowNodeCount).mapNotNull { i ->
                structure.getWindowNodeAt(i).rootViewNode?.let(::ViewFieldNode)
            }
    }
}
