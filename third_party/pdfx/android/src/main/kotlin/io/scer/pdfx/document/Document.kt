package io.scer.pdfx.document

import android.graphics.Bitmap
import android.os.ParcelFileDescriptor
import com.shockwave.pdfium.PdfDocument
import com.shockwave.pdfium.PdfiumCore

/**
 * pdfium-backed PDF document (v2.7.0 engine swap).
 *
 * Replaces android.graphics.pdf.PdfRenderer — the SYSTEM renderer whose
 * behavior differs per Android vendor (several Samsung/MIUI builds ship a
 * PdfRenderer that silently fails on valid files) and which cannot open
 * many perfectly normal PDFs. pdfium is the engine Chrome/Google Drive
 * use: identical behavior on every device, and it repairs/opens a far
 * wider range of documents.
 *
 * pdfium semantics handled here:
 *  * FPDF pages must be loaded (PdfiumCore.openPage) before their size can
 *    be queried or rendered — an unloaded page silently renders NOTHING
 *    (blank bitmap), which is exactly the "gray page" failure mode.
 *  * Calling openPage twice for the same index leaks the previous native
 *    handle, so loads are ref-counted per index and performed exactly
 *    once while the page is referenced.
 *  * All PdfiumCore calls synchronize on the binding's own static lock,
 *    so it is safe to render on a worker thread while the platform thread
 *    opens pages (the Dart controller serializes anyway).
 */
class Document(
    val id: String,
    private val core: PdfiumCore,
    val pdfDocument: PdfDocument,
    val fileDescriptor: ParcelFileDescriptor
) {
    /** Live Page-wrapper ref-count per 0-based page index. */
    private val pageRefs = HashMap<Int, Int>()

    val pagesCount: Int get() = core.getPageCount(pdfDocument)

    val infoMap: Map<String, Any> get() =
        mapOf(
            "id" to id,
            "pagesCount" to pagesCount
        )

    /**
     * Everything a [Page] wrapper needs: the owning handles plus the
     * page's dimensions in PostScript points (same unit the old
     * PdfRenderer reported, so the Dart layer keeps its layout math).
     */
    class LoadedPage(
        val core: PdfiumCore,
        val pdfDocument: PdfDocument,
        val index: Int,
        val width: Int,
        val height: Int
    )

    /**
     * Opens the page by 1-BASED [pageNumber] (pdfx semantics: first page
     * is 1). Loads the native FPDF page on first reference and re-uses it
     * while referenced. Throws [IndexOutOfBoundsException] for out-of-range
     * pages.
     */
    fun openPage(pageNumber: Int): LoadedPage {
        val index = pageNumber - 1
        val count = pagesCount
        if (pageNumber < 1 || index >= count) {
            throw IndexOutOfBoundsException("Page $pageNumber out of range 1..$count")
        }
        val width: Int
        val height: Int
        synchronized(this) {
            val refs = pageRefs[index] ?: 0
            if (refs == 0 && !pdfDocument.hasPage(index)) {
                core.openPage(pdfDocument, index)
            }
            pageRefs[index] = refs + 1
            // Points (1/72") — identical to PdfRenderer.Page dimensions.
            width = core.getPageWidthPoint(pdfDocument, index)
            height = core.getPageHeightPoint(pdfDocument, index)
        }
        if (width <= 0 || height <= 0) {
            // Degenerate page (never seen in the wild, but a 0-sized page
            // would produce a 0-pixel bitmap downstream) — release the
            // reference we just took and fail loudly like PdfRenderer did.
            releasePage(index)
            throw IllegalStateException("Page $pageNumber has no size")
        }
        return LoadedPage(core, pdfDocument, index, width, height)
    }

    /**
     * Renders the (already loaded) 0-based [index] page into [bitmap] at
     * [width] x [height] pixels, annotations included (the same content a
     * desktop viewer shows — form fields, stamps, link appearances).
     */
    fun renderPage(index: Int, bitmap: Bitmap, width: Int, height: Int) {
        core.renderPageBitmap(pdfDocument, bitmap, index, 0, 0, width, height, true)
    }

    /**
     * Drops one reference for the 0-based [index]; when the last wrapper
     * goes away the native page is unloaded, keeping the document's native
     * memory flat across long reading sessions (the old engine allowed
     * only one open page at a time — this restores that memory profile).
     */
    fun releasePage(index: Int) {
        synchronized(this) {
            val refs = (pageRefs[index] ?: 0) - 1
            if (refs > 0) {
                pageRefs[index] = refs
            } else {
                pageRefs.remove(index)
                PdfiumPageUnloader.unloadPage(core, pdfDocument, index)
            }
        }
    }

    /** Opens, runs [block], and always releases the page again. */
    fun <T> withPage(pageNumber: Int, block: (LoadedPage) -> T): T {
        val loaded = openPage(pageNumber)
        try {
            return block(loaded)
        } finally {
            releasePage(loaded.index)
        }
    }

    fun close() {
        synchronized(this) {
            pageRefs.clear()
        }
        // Closes every still-loaded native page, the document and its
        // file descriptor in one call.
        core.closeDocument(pdfDocument)
        // Belt & suspenders — closeDocument already closes the fd, and
        // ParcelFileDescriptor.close() is idempotent.
        try {
            fileDescriptor.close()
        } catch (_: Exception) {
        }
    }
}
