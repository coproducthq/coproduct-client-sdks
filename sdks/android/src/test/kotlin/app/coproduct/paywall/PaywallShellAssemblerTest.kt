package app.coproduct.paywall

import org.junit.Assert.assertTrue
import org.junit.Test

class PaywallShellAssemblerTest {
    @Test
    fun `embeds the body html and the platform script into the shell`() {
        val html = PaywallShellAssembler.assemble(
            bodyHtml = "<div data-cp-cta=\"monthly\">Subscribe</div>",
            platformScriptJs = "window.__coproductInit__();",
        )

        assertTrue(html.contains("<div data-cp-cta=\"monthly\">Subscribe</div>"))
        assertTrue(html.contains("<script>window.__coproductInit__();</script>"))
        assertTrue(html.contains("<!doctype html>"))
    }
}
