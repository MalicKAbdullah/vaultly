package dev.abdullah.vaultkey.print

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintJob
import android.print.PrintManager
import android.print.pdf.PrintedPdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

/**
 * Channel `vaultly/print`: prints the emergency kit through the system
 * print dialog. Dart decides what the page says; this draws the blocks on
 * one page with platform APIs only (PdfDocument, StaticLayout).
 *
 * The result is true when the dialog closed with a job sent to a printer or
 * saved as a PDF, false when the user backed out.
 */
class EmergencyKitPrinter(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "vaultly/print"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "printEmergencyKit") {
            result.notImplemented()
            return
        }
        val jobName = call.argument<String>("jobName")!!
        val blocks = call.argument<List<Map<String, Any>>>("blocks")!!.map(KitBlock::from)
        val manager = activity.getSystemService(Context.PRINT_SERVICE) as PrintManager
        var job: PrintJob? = null
        val adapter = KitAdapter(activity, blocks) {
            result.success(job?.let(::wasSent) ?: false)
        }
        job = manager.print(
            jobName,
            adapter,
            PrintAttributes.Builder()
                .setColorMode(PrintAttributes.COLOR_MODE_MONOCHROME)
                .build(),
        )
    }

    private fun wasSent(job: PrintJob): Boolean =
        job.isQueued || job.isStarted || job.isBlocked || job.isCompleted
}

/** One block of the page, as sent from Dart (`PrintBlock.toMap`). */
internal class KitBlock(
    val style: String,
    val text: String,
    val qrSize: Int,
    val qrModules: ByteArray?,
) {
    companion object {
        fun from(map: Map<String, Any>) = KitBlock(
            style = map["style"] as String,
            text = map["text"] as String,
            qrSize = (map["qrSize"] as Int?) ?: 0,
            qrModules = map["qrModules"] as ByteArray?,
        )
    }
}

/**
 * Lays the blocks out top to bottom on a single page of whatever paper the
 * user picks. Content that would run past the bottom margin is scaled down
 * to fit, so nothing is ever clipped onto a second page.
 */
internal class KitAdapter(
    private val context: Context,
    blocks: List<KitBlock>,
    private val onDone: () -> Unit,
) : PrintDocumentAdapter() {

    // Dropped when the dialog closes so the secrets do not outlive the job.
    private var blocks: List<KitBlock>? = blocks
    private var attributes: PrintAttributes? = null

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onLayoutCancelled()
            return
        }
        attributes = newAttributes
        val info = PrintDocumentInfo.Builder("vaultly-emergency-kit.pdf")
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .setPageCount(1)
            .build()
        callback.onLayoutFinished(info, newAttributes != oldAttributes)
    }

    override fun onWrite(
        pages: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal,
        callback: WriteResultCallback,
    ) {
        val content = blocks
        if (content == null) {
            callback.onWriteFailed(null)
            return
        }
        val document = PrintedPdfDocument(context, attributes!!)
        try {
            val page = document.startPage(0)
            KitPage(content).draw(page.canvas, page.info.pageWidth.toFloat(), page.info.pageHeight.toFloat())
            document.finishPage(page)
            if (cancellationSignal.isCanceled) {
                callback.onWriteCancelled()
                return
            }
            FileOutputStream(destination.fileDescriptor).use { document.writeTo(it) }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (e: java.io.IOException) {
            callback.onWriteFailed(null)
        } finally {
            document.close()
        }
    }

    override fun onFinish() {
        blocks = null
        onDone()
    }
}

/** Draws the blocks on a page measured in PostScript points. */
internal class KitPage(private val blocks: List<KitBlock>) {

    private val margin = 54f
    private val ink = Color.BLACK
    private val grey = Color.rgb(0x55, 0x55, 0x55)

    private fun paint(size: Float, bold: Boolean = false, mono: Boolean = false, color: Int = ink) =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            this.color = color
            typeface = Typeface.create(
                if (mono) Typeface.MONOSPACE else Typeface.SANS_SERIF,
                if (bold) Typeface.BOLD else Typeface.NORMAL,
            )
        }

    private fun layout(text: String, paint: TextPaint, width: Int): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(0f, 1.25f)
            .build()

    /** Space above a block, then the block's own height. */
    private class Measured(val gap: Float, val height: Float, val draw: (Canvas) -> Unit)

    private fun measure(block: KitBlock, width: Float): Measured {
        val w = width.toInt()
        return when (block.style) {
            "title" -> text(0f, layout(block.text, paint(22f, bold = true), w))
            "caption" -> text(4f, layout(block.text, paint(9.5f, color = grey), w))
            "heading" -> text(20f, layout(block.text, paint(14f, bold = true), w))
            "text" -> text(6f, layout(block.text, paint(10.5f), w))
            "secret" -> text(8f, layout(block.text, paint(15f, bold = true, mono = true), w))
            "warning" -> {
                val pad = 8f
                val body = layout(block.text, paint(10.5f, bold = true), (width - 2 * pad).toInt())
                val h = body.height + 2 * pad
                Measured(14f, h) { canvas ->
                    val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = 1.2f
                        color = ink
                    }
                    canvas.drawRoundRect(RectF(0f, 0f, width, h), 4f, 4f, border)
                    canvas.save()
                    canvas.translate(pad, pad)
                    body.draw(canvas)
                    canvas.restore()
                }
            }
            "qr" -> {
                val side = 110f
                val n = block.qrSize
                val modules = block.qrModules!!
                Measured(8f, side) { canvas ->
                    val cell = side / n
                    val fill = Paint().apply { color = ink; style = Paint.Style.FILL }
                    for (row in 0 until n) {
                        for (col in 0 until n) {
                            if (modules[row * n + col].toInt() == 1) {
                                // Slight overlap closes hairline gaps between modules.
                                canvas.drawRect(
                                    col * cell, row * cell,
                                    (col + 1) * cell + 0.1f, (row + 1) * cell + 0.1f,
                                    fill,
                                )
                            }
                        }
                    }
                }
            }
            "writeIn" -> {
                val label = layout(block.text, paint(9.5f, color = grey), w)
                val lineGap = 26f
                Measured(18f, label.height + lineGap) { canvas ->
                    label.draw(canvas)
                    val y = label.height + lineGap
                    val line = Paint().apply { color = ink; strokeWidth = 0.8f }
                    canvas.drawLine(0f, y, width, y, line)
                }
            }
            else -> throw IllegalArgumentException("Unknown block style ${block.style}")
        }
    }

    private fun text(gap: Float, layout: StaticLayout) =
        Measured(gap, layout.height.toFloat()) { layout.draw(it) }

    /** Total content height at full size, for tests and the fit check. */
    fun contentHeight(pageWidth: Float): Float =
        blocks.map { measure(it, pageWidth - 2 * margin) }.sumOf { (it.gap + it.height).toDouble() }.toFloat()

    fun draw(canvas: Canvas, pageWidth: Float, pageHeight: Float) {
        val available = pageHeight - 2 * margin
        val total = contentHeight(pageWidth)
        val scale = if (total > available) available / total else 1f
        // Measured at the width the scaled content will occupy, so lines
        // still reach the right margin after scaling.
        val width = (pageWidth - 2 * margin) / scale
        val measured = blocks.map { measure(it, width) }
        canvas.save()
        canvas.translate(margin, margin)
        canvas.scale(scale, scale)
        var y = 0f
        for (m in measured) {
            y += m.gap
            canvas.save()
            canvas.translate(0f, y)
            m.draw(canvas)
            canvas.restore()
            y += m.height
        }
        canvas.restore()
    }
}
