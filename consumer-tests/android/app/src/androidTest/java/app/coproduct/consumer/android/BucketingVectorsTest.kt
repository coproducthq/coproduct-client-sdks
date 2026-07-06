package app.coproduct.consumer.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BucketingVectorsTest {

    private data class Vector(
        val ruleId: String,
        val targetingKey: String,
        val suffix: String,
        val expectedBucket: Long,
    )

    private fun loadVectors(): List<Vector> {
        val context = InstrumentationRegistry.getInstrumentation().context
        val raw = context.assets.open("bucketing_vectors.json")
            .bufferedReader()
            .use { it.readText() }
        val array = JSONArray(raw)
        return (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            Vector(
                ruleId = o.getString("rule_id"),
                targetingKey = o.getString("targeting_key"),
                suffix = o.getString("suffix"),
                expectedBucket = o.getLong("expected_bucket"),
            )
        }
    }

    @Test
    fun bucketForVectorsMatchesGoldenVectors() {
        val vectors = loadVectors()
        assertEquals("expected 4 vectors in fixture", 4, vectors.size)
        vectors.forEachIndexed { i, v ->
            val actual = uniffi.coproduct_ffi_uniffi.bucketForVectors(v.ruleId, v.targetingKey, v.suffix)
            assertEquals(
                "vector[$i] ruleId=${v.ruleId} targetingKey=${v.targetingKey} suffix=${v.suffix}",
                v.expectedBucket,
                actual.toLong(),
            )
        }
    }
}
