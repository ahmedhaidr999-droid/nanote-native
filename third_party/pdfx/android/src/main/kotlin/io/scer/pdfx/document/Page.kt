package io.scer.pdfx.document

import android.graphics.Bitmap
import io.scer.pdfx.utils.toFile
import java.io.File

/**
 * A pdfium-backed page wrapper.
 *
 * The native FPDF page is loaded while this wrapper (or any sibling
 * wrapper for the same index) is alive — the owning [Document]
 * ref-counts loads. [close] releases the wrapper and unloads the page
 * when it was the last one, mirroring the old engine's tight page
 * lifecycle instead of leaking native memory.
 *
 * v2.7.0 note: the bitmap is now RECYCLED after every render — the old
 * implementation never recycled, which contributed to the memory pressure
 * behind the v2.5.x OOM class of failures.
 */
class Page(
    val id: String,
    val documentId: String,
    private val document: Document,
    private val pageIndex: Int,
    val width: Int,
    val height: Int
) {
    /**
     * 0-based page index — matches the old PdfRenderer.Page.getIndex()
     * value that was reported as "pageNumber" to Dart (behavior parity).
     */
    private val number: Int get() = pageIndex

    val infoMap: Map<String, Any>
        get() =
            mapOf(
                "documentId" to documentId,
                "id" to id,
                "pageNumber" to number,
                "width" to width,
                "height" to height
            )

    fun close() {
        document.releasePage(pageIndex)
    }

    fun render(
        file: File,
        width: Int,
        height: Int,
        background: Int,
        format: Int,
        crop: Boolean,
        cropX: Int,
        cropY: Int,
        cropW: Int,
        cropH: Int,
        quality: Int,
        @Suppress("UNUSED_PARAMETER") forPrint: Boolean
    ): Data {
        val bitmap = Bitmap.createBitmap(
            width,
            height,
            Bitmap.Config.ARGB_8888)
        try {
            bitmap.eraseColor(background)
            // Full-page raster at exactly the requested size. The native
            // page is guaranteed loaded (openPage ran before this wrapper
            // was created), so this call cannot hit pdfium's silent
            // "page not loaded -> blank bitmap" path. Annotations are
            // rendered (true) — the same content desktop viewers show.
            document.renderPage(pageIndex, bitmap, width, height)

            if (crop && (cropW != width || cropH != height)) {
                val cropped = Bitmap.createBitmap(bitmap, cropX, cropY, cropW, cropH)
                try {
                    cropped.toFile(file, format, quality)
                    return Data(
                        cropW,
                        cropH,
                        file.absolutePath
                    )
                } finally {
                    cropped.recycle()
                }
            } else {
                bitmap.toFile(file, format, quality)
                return Data(
                    width,
                    height,
                    file.absolutePath
                )
            }
        } finally {
            bitmap.recycle()
        }
    }

    data class Data(
        val width: Int,
        val height: Int,
        val path: String
    ) {
        val toMap: Map<String, Any>
            get() =
                mapOf(
                    "width" to width,
                    "height" to height,
                    "path" to path
                )

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false

            other as Data

            if (!path.contentEquals(other.path)) return false

            return true
        }

        override fun hashCode(): Int = width.hashCode()
            .times(31).plus(height.hashCode())
            .times(31).plus(path.hashCode())
    }
}
