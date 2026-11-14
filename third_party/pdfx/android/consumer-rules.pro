# pdfium-android is driven reflectively by PdfiumPageUnloader (its
# private static lock, private nativeClosePage and package-private page
# map) — keep the binding's classes and members exactly as published.
-keep class com.shockwave.pdfium.** { *; }
