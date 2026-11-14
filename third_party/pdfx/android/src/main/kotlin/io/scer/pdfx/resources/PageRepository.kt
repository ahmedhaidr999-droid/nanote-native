package io.scer.pdfx.resources

import io.scer.pdfx.document.Document
import io.scer.pdfx.document.Page
import io.scer.pdfx.utils.randomID

class PageRepository : Repository<Page>() {
    /**
     * Registers a page opened via [Document.openPage] and gives it a
     * repository id. The returned wrapper keeps the native page loaded
     * until [close] drops the last reference for its index.
     */
    fun register(document: Document, loaded: Document.LoadedPage): Page {
        val id = randomID
        val page = Page(
            id,
            document.id,
            document,
            loaded.index,
            loaded.width,
            loaded.height
        )
        set(id, page)
        return page
    }

    public override fun close(id: String) {
        get(id).close()
        super.close(id)
    }
}
