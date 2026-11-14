package io.scer.pdfx

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import android.util.SparseArray
import android.view.Surface
import androidx.annotation.RequiresApi
import com.shockwave.pdfium.PdfDocument
import com.shockwave.pdfium.PdfiumCore
import dev.flutter.pigeon.Pigeon
import io.flutter.BuildConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.view.TextureRegistry
import io.flutter.view.TextureRegistry.SurfaceProducer.Callback
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.PageRepository
import io.scer.pdfx.resources.RepositoryItemNotFoundException
import io.scer.pdfx.utils.CreateRendererException
import io.scer.pdfx.utils.randomFilename
import io.scer.pdfx.utils.toFile
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * v2.7.0 — the PDF engine behind this bridge is pdfium (Google Chrome's
 * PDF engine) instead of the per-device system PdfRenderer.
 *
 * Why: the system renderer's behavior varies by Android vendor (several
 * Samsung/MIUI builds ship one that fails on perfectly valid files) and
 * it refuses a wide range of normal PDFs. pdfium renders identically on
 * every device, repairs damaged xref tables, and powers Chrome / Google
 * Drive — the same engine class professional annotation apps use.
 *
 * The Pigeon surface is UNCHANGED, so the Dart layer needs no edits.
 */
@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class Messages(private val binding : FlutterPlugin.FlutterPluginBinding,
               private val documents: DocumentRepository,
               private val pages: PageRepository) : Pigeon.PdfxApi {

    /** One shared pdfium core — all its calls lock internally. */
    private val pdfium: PdfiumCore = PdfiumCore(binding.applicationContext)

    private val surfaceProducers: SparseArray<TextureRegistry.SurfaceProducer> = SparseArray()
    private val documentStatesPerSurface: SparseArray<Pigeon.UpdateTextureMessage> = SparseArray()

    override fun openDocumentData(
        message: Pigeon.OpenDataMessage,
        result: Pigeon.Result<Pigeon.OpenReply>
    ) {
        val resultResponse = Pigeon.OpenReply()
        try {
            val documentRenderer = openDataDocument(message.data!!, message.password)
            val document = documents.register(documentRenderer, pdfium)
            resultResponse.id = document.id
            resultResponse.pagesCount = document.pagesCount.toLong()
            result.success(resultResponse)
        } catch (e: IOException) {
            result.error(PdfRendererException("pdf_renderer", "Can't open file", null))
        } catch (e: CreateRendererException) {
            result.error(PdfRendererException("pdf_renderer", "Can't create PDF renderer", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun openDocumentFile(
        message: Pigeon.OpenPathMessage,
        result: Pigeon.Result<Pigeon.OpenReply>
    ) {
        val resultResponse = Pigeon.OpenReply()
        try {
            val path = message.path
            val documentRenderer = openFileDocument(File(path!!), message.password)
            val document = documents.register(documentRenderer, pdfium)
            resultResponse.id = document.id
            resultResponse.pagesCount = document.pagesCount.toLong()
            result.success(resultResponse)
        } catch (e: NullPointerException) {
            result.error(PdfRendererException("pdf_renderer", "Need call arguments: path", null))
        } catch (e: FileNotFoundException) {
            result.error(PdfRendererException("pdf_renderer", "File not found", null))
        } catch (e: IOException) {
            result.error(PdfRendererException("pdf_renderer", "Can't open file", null))
        } catch (e: CreateRendererException) {
            result.error(PdfRendererException("pdf_renderer", "Can't create PDF renderer", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun openDocumentAsset(
        message: Pigeon.OpenPathMessage,
        result: Pigeon.Result<Pigeon.OpenReply>
    ) {
        val resultResponse = Pigeon.OpenReply()
        try {
            val path = message.path
            val documentRenderer = openAssetDocument(path!!, message.password)
            val document = documents.register(documentRenderer, pdfium)
            resultResponse.id = document.id
            resultResponse.pagesCount = document.pagesCount.toLong()
            result.success(resultResponse)
        } catch (e: NullPointerException) {
            result.error(PdfRendererException("pdf_renderer", "Need call arguments: path", null))
        } catch (e: FileNotFoundException) {
            result.error(PdfRendererException("pdf_renderer", "File not found", null))
        } catch (e: IOException) {
            result.error(PdfRendererException("pdf_renderer", "Can't open file", null))
        } catch (e: CreateRendererException) {
            result.error(PdfRendererException("pdf_renderer", "Can't create PDF renderer", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun closeDocument(message: Pigeon.IdMessage) {
        try {
            val id = message.id
            documents.close(id!!)
        } catch (e: NullPointerException) {
            throw PdfRendererException("pdf_renderer", "Need call arguments: id!", null)
        } catch (e: RepositoryItemNotFoundException) {
            throw PdfRendererException("pdf_renderer", "Document not exist in documents repository", null)
        } catch (e: Exception) {
            throw PdfRendererException("pdf_renderer", "Unknown error", null)
        }
    }

    override fun getPage(
        message: Pigeon.GetPageMessage,
        result: Pigeon.Result<Pigeon.GetPageReply>
    ) {
        val resultResponse = Pigeon.GetPageReply()
        try {
            val documentId = message.documentId!!
            val pageNumber = message.pageNumber!!.toInt()
            val document = documents.get(documentId)

            if (message.autoCloseAndroid!!) {
                // Size-only query: open, read dimensions, release.
                document.withPage(pageNumber) { loaded ->
                    resultResponse.width = loaded.width.toDouble()
                    resultResponse.height = loaded.height.toDouble()
                }
            } else {
                val loaded = document.openPage(pageNumber)
                val page = pages.register(document, loaded)
                resultResponse.id = page.id
                resultResponse.width = page.width.toDouble()
                resultResponse.height = page.height.toDouble()
            }

            result.success(resultResponse)
        } catch (e: NullPointerException) {
            result.error(PdfRendererException("pdf_renderer", "Need call arguments: documentId & page!", null))
        } catch (e: RepositoryItemNotFoundException) {
            result.error(PdfRendererException("pdf_renderer", "Document not exist in documents", null))
        } catch (e: Exception) {
            result.error(PdfRendererException("pdf_renderer", "Unknown error", null))
        }
    }

    override fun renderPage(
        message: Pigeon.RenderPageMessage,
        result: Pigeon.Result<Pigeon.RenderPageReply>
    ) {
        val resultResponse = Pigeon.RenderPageReply()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val pageId = message.pageId ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Page ID is null", null))
                    return@launch
                }

                val width = message.width?.toInt() ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Width is null", null))
                    return@launch
                }

                val height = message.height?.toInt() ?: run {
                    result.error(PdfRendererException("pdf_renderer", "Height is null", null))
                    return@launch
                }

                val format = message.format?.toInt() ?: 1
                val backgroundColor = message.backgroundColor
                val color = backgroundColor?.let { Color.parseColor(it) } ?: Color.TRANSPARENT

                val crop = message.crop ?: false
                val cropX = if (crop) message.cropX?.toInt() ?: 0 else 0
                val cropY = if (crop) message.cropY?.toInt() ?: 0 else 0
                val cropH = if (crop) message.cropHeight?.toInt() ?: 0 else 0
                // Fixed: upstream pdfx read `width` here instead of
                // `cropWidth` (dead code for this app — it never crops —
                // but now it is correct if ever used).
                val cropW = if (crop) message.cropWidth?.toInt() ?: 0 else 0

                val quality = message.quality?.toInt() ?: 100
                val forPrint = message.forPrint ?: false

                val page = pages.get(pageId)

                val tempOutFileExtension = when (format) {
                    0 -> "jpg"
                    1 -> "png"
                    2 -> "webp"
                    else -> "jpg"
                }

                val tempOutFolder = File(binding.applicationContext.cacheDir, "pdf_renderer_cache").apply {
                    mkdirs()
                }

                val tempOutFile = File(tempOutFolder, "$randomFilename.$tempOutFileExtension")

                //  background thread render
                val pageImage = page.render(
                    file = tempOutFile,
                    width = width,
                    height = height,
                    background = color,
                    format = format,
                    crop = crop,
                    cropX = cropX,
                    cropY = cropY,
                    cropW = cropW,
                    cropH = cropH,
                    quality = quality,
                    forPrint = forPrint,
                )

                withContext(Dispatchers.Main) {
                    resultResponse.path = pageImage.path
                    resultResponse.width = pageImage.width.toLong()
                    resultResponse.height = pageImage.height.toLong()
                    result.success(resultResponse)
                }
            } catch (e: Throwable) {
                // NANOTE FIX (kept from v2.6.0, upstream pdfx 2.11 bug): the
                // render coroutine used to catch only `Exception`.
                // `Bitmap.createBitmap` for a full-page raster can throw
                // `OutOfMemoryError` (an `Error`, NOT an `Exception`) under
                // memory pressure - the catch was skipped, `result.error(...)`
                // never ran, the platform channel reply was never sent and
                // the Dart-side render future NEVER COMPLETED. Every
                // serialized renderer stalled right after the first
                // successful page ("only page 1 renders"). Catching
                // Throwable guarantees the reply is always delivered; the
                // caller then retries/reopens as a normal failure.
                withContext(Dispatchers.Main) {
                    result.error(PdfRendererException("pdf_renderer", "Unexpected error", e))
                }
            }
        }
    }

    override fun closePage(message: Pigeon.IdMessage) {
        try {
            val id = message.id!!
            pages.close(id)
        } catch (e: NullPointerException) {
            throw PdfRendererException("pdf_renderer", "Need call arguments: id!", null)
        } catch (e: RepositoryItemNotFoundException) {
            throw PdfRendererException("pdf_renderer", "Page not exist in pages repository", null)
        } catch (e: Exception) {
            throw PdfRendererException("pdf_renderer", "Unknown error", null)
        }
    }

    override fun registerTexture(): Pigeon.RegisterTextureReply {
        val surfaceProducer = binding.textureRegistry.createSurfaceProducer()
        val id = surfaceProducer.id().toInt()
        surfaceProducers.put(id, surfaceProducer)

        surfaceProducer.setCallback(object : Callback {
            override fun onSurfaceAvailable() {
                documentStatesPerSurface[id]?.let { documentUpdate ->
                    onDocumentOrSurfaceChanged(
                        surfaceProducer.surface,
                        documentUpdate,
                        result = null,
                    )
                }
            }

            override fun onSurfaceCleanup() {
                // ignore - Surface is used once to draw bitmap
            }
        })

        val result = Pigeon.RegisterTextureReply()
        result.id = id.toLong()
        return result
    }

    override fun updateTexture(
        message: Pigeon.UpdateTextureMessage,
        result: Pigeon.Result<Void>
    ) {
        val texId = message.textureId!!.toInt()
        val surfaceProducer = surfaceProducers[texId]
        val texWidth = message.textureWidth!!.toInt()
        val texHeight = message.textureHeight!!.toInt()
        if (texWidth != 0 && texHeight != 0) {
            surfaceProducer.setSize(texWidth, texHeight)
        }
        documentStatesPerSurface.put(texId, message)
        onDocumentOrSurfaceChanged(surfaceProducer.surface, message, result)
    }

    private fun onDocumentOrSurfaceChanged(
        surface: Surface,
        message: Pigeon.UpdateTextureMessage,
        result: Pigeon.Result<Void>?,
    ) {
        val pageNumber = message.pageNumber!!.toInt()
        val document = documents.get(message.documentId!!)
        document.withPage(pageNumber) { loaded ->
            val fullWidth = message.fullWidth ?: loaded.width.toDouble()
            val fullHeight = message.fullHeight ?: loaded.height.toDouble()
            val destX = message.destinationX!!.toInt()
            val destY = message.destinationY!!.toInt()
            val width = message.width!!.toInt()
            val height = message.height!!.toInt()
            val srcX = message.sourceX!!.toInt()
            val srcY = message.sourceY!!.toInt()
            val backgroundColor = message.backgroundColor

            if (width <= 0 || height <= 0) {
                result?.error(PdfRendererException("pdf_renderer", "updateTexture width/height == 0", null))
                return@withPage
            }

            try {
                // pdfium renders whole pages; render the page once at the
                // requested full size, then blit the requested source rect
                // to the destination rect (the notebook pipeline does not
                // use the texture path — correctness is what matters here).
                val fullW = fullWidth.toInt().coerceAtLeast(1).coerceAtMost(4096)
                val fullH = fullHeight.toInt().coerceAtLeast(1).coerceAtMost(4096)
                val bmp = Bitmap.createBitmap(fullW, fullH, Bitmap.Config.ARGB_8888)
                try {
                    if (backgroundColor != null) {
                        bmp.eraseColor(Color.parseColor(backgroundColor))
                    }
                    pdfium.renderPageBitmap(loaded.pdfDocument, bmp, loaded.index, 0, 0, fullW, fullH, true)

                    surface.use {
                        val canvas = it.lockCanvas(Rect(destX, destY, destX + width, destY + height))
                        try {
                            canvas.drawBitmap(
                                bmp,
                                Rect(srcX, srcY, srcX + width, srcY + height),
                                Rect(destX, destY, destX + width, destY + height),
                                null,
                            )
                        } finally {
                            it.unlockCanvasAndPost(canvas)
                        }
                    }
                    result?.success(null)
                } finally {
                    bmp.recycle()
                }
            } catch (e: Exception) {
                result?.error(PdfRendererException("pdf_renderer", "updateTexture Unknown error", null))
            }
        }
    }

    override fun resizeTexture(
        message: Pigeon.ResizeTextureMessage,
        result: Pigeon.Result<Void>
    ) {
        val texId = message.textureId!!.toInt()
        val width = message.width!!.toInt()
        val height = message.height!!.toInt()
        val tex = surfaceProducers[texId]
        tex?.setSize(width, height)
        result.success(null)
    }

    override fun unregisterTexture(message: Pigeon.UnregisterTextureMessage) {
        val id = message.id!!.toInt()
        val surfaceProducer = surfaceProducers[id]
        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducers.remove(id)
    }

    private fun openDataDocument(data: ByteArray, password: String?): Pair<ParcelFileDescriptor, PdfDocument> {
        val tempDataFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        if (!tempDataFile.exists()) {
            tempDataFile.writeBytes(data)
        }
        Log.d("pdf_renderer", "OpenDataDocument. Created file: " + tempDataFile.path)
        return openFileDocument(tempDataFile, password)
    }

    private fun openAssetDocument(assetPath: String, password: String?): Pair<ParcelFileDescriptor, PdfDocument> {
        val fullAssetPath = binding.flutterAssets.getAssetFilePathByName(assetPath)
        val tempAssetFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        if (!tempAssetFile.exists()) {
            val inputStream = binding.applicationContext.assets.open(fullAssetPath)
            inputStream.toFile(tempAssetFile)
            inputStream.close()
        }
        Log.d("pdf_renderer", "OpenAssetDocument. Created file: " + tempAssetFile.path)
        return openFileDocument(tempAssetFile, password)
    }

    private fun openFileDocument(file: File, password: String?): Pair<ParcelFileDescriptor, PdfDocument> {
        Log.d("pdf_renderer", "OpenFileDocument. File: " + file.path)
        val fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return try {
            val pdfDocument = pdfium.newDocument(fileDescriptor, password)
            Pair(fileDescriptor, pdfDocument)
        } catch (t: Throwable) {
            // Never leak the fd when pdfium refuses the document.
            try {
                fileDescriptor.close()
            } catch (_: Exception) {
            }
            throw t
        }
    }
}

class PdfRendererException internal constructor(code: String?, message: String?, details: Any?) :
    RuntimeException(message) {
    private val code: String?
    private var details: Any? = null

    companion object {
        private const val TAG = "PdfRendererException#"
    }

    init {
        if (BuildConfig.DEBUG && code == null) {
            io.flutter.Log.e(TAG, "Parameter code must not be null.")
        }
        this.code = code
        if (details != null) {
            this.details = details
        }
    }
}

fun <R> Surface.use(block: (Surface) -> R): R {
    try {
        return block(this)
    }
    finally {
        this.release()
    }
}
