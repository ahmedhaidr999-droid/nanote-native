package io.scer.pdfx.resources

import android.os.ParcelFileDescriptor
import com.shockwave.pdfium.PdfDocument
import com.shockwave.pdfium.PdfiumCore
import io.scer.pdfx.document.Document
import io.scer.pdfx.utils.randomID

class DocumentRepository : Repository<Document>() {
    /**
     * Register an opened pdfium document in the repository.
     * @returns document id
     */
    fun register(getPair: Pair<ParcelFileDescriptor, PdfDocument>?, core: PdfiumCore): Document {
        val id = randomID
        val (fileDescriptor, pdfDocument) = getPair!!
        val document = Document(id, core, pdfDocument, fileDescriptor)
        set(id, document)
        return document
    }

    public override fun close(id: String) {
        get(id).close()
        super.close(id)
    }
}
