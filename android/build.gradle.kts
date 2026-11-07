allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ---------------------------------------------------------------------------
// Legacy-plugin compatibility shim (isar_flutter_libs 3.1.0+1 — carried ONLY
// for the one-time Isar→Drift data migration).
//
// 1) Namespace: isar_flutter_libs predates AGP 8's required `namespace` DSL
//    but still declares `package` in its AndroidManifest.xml. Inject the
//    manifest package as the namespace, or configuration fails with
//    "Namespace not specified".
//
// 2) compileSdk floor: it compiles against an old SDK but its AndroidX
//    dependencies reference android:attr/lStar (API 31+). Raise every
//    Android library module to 36.
//
// Runs via afterEvaluate hooks registered BEFORE each child is evaluated
// (root configures first) — i.e. before AGP's own afterEvaluate variant
// creation, exactly like the proven v2.x Groovy shim.
// ---------------------------------------------------------------------------
subprojects {
    val sub = this
    if (sub.name == "app") return@subprojects
    sub.afterEvaluate {
        val androidExt = sub.extensions.findByName("android") ?: return@afterEvaluate
        try {
            val getNamespace = androidExt.javaClass.getMethod("getNamespace")
            val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
            val ns = getNamespace.invoke(androidExt) as? String
            if (ns.isNullOrEmpty()) {
                val mf = sub.file("src/main/AndroidManifest.xml")
                if (mf.exists()) {
                    val pkg = Regex("package=\"([^\"]+)\"").find(mf.readText())?.groupValues?.get(1)
                    if (!pkg.isNullOrEmpty()) {
                        setNamespace.invoke(androidExt, pkg)
                        sub.logger.lifecycle("Injected namespace '$pkg' into ${sub.name}")
                    }
                }
            }
            val setCompileSdk = androidExt.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
            setCompileSdk.invoke(androidExt, 36)
        } catch (e: Exception) {
            sub.logger.warn("legacy plugin fix skipped for ${sub.name}: ${e.message}")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
