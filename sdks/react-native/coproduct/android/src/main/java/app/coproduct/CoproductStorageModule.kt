// The app directories the SDK keeps its files in. See src/NativeCoproductStorage.ts
package app.coproduct

import com.facebook.fbreact.specs.NativeCoproductStorageSpec
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.annotations.ReactModule
import java.io.File
import java.io.IOException

@ReactModule(name = CoproductStorageModule.NAME)
class CoproductStorageModule(reactContext: ReactApplicationContext) :
  NativeCoproductStorageSpec(reactContext) {

  override fun getName(): String {
    return NAME
  }

  // getCacheDir and getFilesDir are the directories react-native-fs reported
  // as CachesDirectoryPath and DocumentDirectoryPath, so the snapshot cache and
  // the files earlier releases wrote stay where they were
  override fun cachesDirectoryPath(): String {
    return reactApplicationContext.cacheDir.absolutePath
  }

  override fun readDocumentFile(name: String): String? {
    val file = documentFile(name) ?: return null
    return try {
      if (file.isFile) file.readText(Charsets.UTF_8) else null
    } catch (e: IOException) {
      null
    }
  }

  // Writes beside the target and renames over it, so a crash mid-write leaves
  // the previous contents rather than a truncated file
  override fun writeDocumentFile(name: String, contents: String): Boolean {
    val file = documentFile(name) ?: return false
    val temp = File(file.parentFile, "${file.name}.tmp")
    return try {
      file.parentFile?.mkdirs()
      temp.writeText(contents, Charsets.UTF_8)
      temp.renameTo(file) || run {
        temp.delete()
        false
      }
    } catch (e: IOException) {
      temp.delete()
      false
    }
  }

  // A file directly inside getFilesDir, or null when name is not a bare file name
  private fun documentFile(name: String): File? {
    if (name.isEmpty() || name.contains('/') || name == "." || name == "..") return null
    return File(reactApplicationContext.filesDir, name)
  }

  companion object {
    const val NAME = "CoproductStorage"
  }
}
