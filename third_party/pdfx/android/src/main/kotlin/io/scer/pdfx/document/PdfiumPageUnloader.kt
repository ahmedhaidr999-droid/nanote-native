package io.scer.pdfx.document

import android.util.Log
import com.shockwave.pdfium.PdfDocument
import com.shockwave.pdfium.PdfiumCore

/**
 * Optional per-page unloading for com.github.barteksc:pdfium-android:1.9.0.
 *
 * The binding's public API can LOAD pages (PdfiumCore.openPage) but only
 * closeDocument releases them — there is no public unload for a single
 * page. Letting pages accumulate across a long reading session grows
 * native memory without bound (each FPDF_PAGE keeps its parsed object
 * list alive), which is precisely the OOM pressure this app must avoid.
 *
 * This helper reflectively reaches the binding's own private
 * nativeClosePage(long) and its per-document page map, and invokes them
 * under the SAME static lock PdfiumCore uses for every native call, so
 * the unload is strictly serialized with renders (pdfium document handles
 * must not be touched concurrently).
 *
 * Failure containment: if ANY part of the reflection does not resolve
 * (renamed in a future binding, aggressive shrinking…), unloadPage()
 * simply returns false and the page stays loaded until the document
 * closes — a graceful, slightly heavier fallback that can never break
 * rendering or crash.
 */
internal object PdfiumPageUnloader {
    private const val TAG = "PdfiumPageUnloader"

    /** PdfiumCore's private static lock — null when unreachable. */
    private val coreLock: Any? by lazy {
        try {
            val f = PdfiumCore::class.java.getDeclaredField("lock")
            f.isAccessible = true
            f.get(null)
        } catch (t: Throwable) {
            Log.w(TAG, "core lock unreachable, page unload disabled: $t")
            null
        }
    }

    /** private native void nativeClosePage(long pagePtr). */
    private val closePageMethod by lazy {
        try {
            val m = PdfiumCore::class.java
                .getDeclaredMethod("nativeClosePage", java.lang.Long.TYPE)
            m.isAccessible = true
            m
        } catch (t: Throwable) {
            Log.w(TAG, "nativeClosePage unreachable, page unload disabled: $t")
            null
        }
    }

    /** PdfDocument's package-private Map<Integer, Long> of loaded pages. */
    private val pagesField by lazy {
        try {
            val f = PdfDocument::class.java.getDeclaredField("mNativePagesPtr")
            f.isAccessible = true
            f
        } catch (t: Throwable) {
            Log.w(TAG, "page map unreachable, page unload disabled: $t")
            null
        }
    }

    /**
     * Unloads the native page [index] from [doc]. Returns true when the
     * page is no longer loaded afterwards (or never was); false when the
     * reflective path is unavailable and the caller should keep the page
     * loaded until document close.
     */
    fun unloadPage(core: PdfiumCore, doc: PdfDocument, index: Int): Boolean {
        val method = closePageMethod ?: return false
        val field = pagesField ?: return false
        val monitor = coreLock ?: return false
        return synchronized(monitor) {
            try {
                @Suppress("UNCHECKED_CAST")
                val pages = field.get(doc) as? Map<Int, Long> ?: return false
                val ptr = pages[index]
                if (ptr == null) {
                    // Not loaded — nothing to do.
                    return true
                }
                method.invoke(core, ptr)
                (pages as? MutableMap<Int, Long>)?.remove(index)
                true
            } catch (t: Throwable) {
                Log.w(TAG, "unloadPage($index) failed, keeping page loaded: $t")
                false
            }
        }
    }
}
