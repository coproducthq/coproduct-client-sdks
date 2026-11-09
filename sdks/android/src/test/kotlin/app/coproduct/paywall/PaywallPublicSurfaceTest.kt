package app.coproduct.paywall

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// Kotlin declarations are public unless marked otherwise, and an internal
// top-level declaration still compiles to a public JVM member, so reflection
// cannot tell the two apart. Reading the source pins the visibility instead.
class PaywallPublicSurfaceTest {
    @Test
    fun snapshotCacheDeclarationsStayInternal() {
        val topLevelDeclaration = Regex(
            "^(?:(?:public|internal|private|open|abstract|final|sealed|data|const|inline|suspend)\\s+)*" +
                "(?:class|object|interface|typealias|fun|val|var)\\b",
        )
        val declarations = File("src/main/kotlin/app/coproduct/paywall/SnapshotCache.kt")
            .readLines()
            .filter { topLevelDeclaration.containsMatchIn(it) }

        assertTrue("no declarations found", declarations.isNotEmpty())
        assertEquals(emptyList<String>(), declarations.filterNot { it.startsWith("internal ") })
    }
}
