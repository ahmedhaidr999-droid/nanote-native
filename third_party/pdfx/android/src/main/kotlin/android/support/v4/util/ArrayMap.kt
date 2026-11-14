@file:Suppress("unused")

package android.support.v4.util

/**
 * Bytecode-compatibility shim for com.github.barteksc:pdfium-android:1.9.0.
 *
 * The binding's PdfDocument constructs android.support.v4.util.ArrayMap
 * (and its POM declares the whole legacy support-v4, whose classes clash
 * with AndroidX during checkReleaseDuplicateClasses). The support
 * dependency is excluded at the Gradle level; this drop-in class provides
 * the single class the binding's bytecode actually references, delegating
 * to the identical framework implementation (android.util.ArrayMap —
 * exactly what support-v4's ArrayMap wrapped on API 14+; it is final, so
 * the shim delegates instead of extending).
 */
class ArrayMap<K, V>(
    private val backing: android.util.ArrayMap<K, V> = android.util.ArrayMap()
) : MutableMap<K, V> by backing
