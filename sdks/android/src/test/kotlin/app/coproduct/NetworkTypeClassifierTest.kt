package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkTypeClassifierTest {
    private fun facts(
        satisfied: Boolean = false,
        wifi: Boolean = false,
        cellular: Boolean = false,
        ethernet: Boolean = false,
    ) = NetworkPathFacts(satisfied = satisfied, wifi = wifi, cellular = cellular, ethernet = ethernet)

    @Test
    fun unsatisfiedIsNone() {
        assertEquals("none", NetworkTypeClassifier.classify(facts(satisfied = false)))
    }

    @Test
    fun unsatisfiedIsNoneEvenWithAnInterfaceNominallyPresent() {
        assertEquals("none", NetworkTypeClassifier.classify(facts(satisfied = false, wifi = true)))
    }

    @Test
    fun satisfiedWifi() {
        assertEquals("wifi", NetworkTypeClassifier.classify(facts(satisfied = true, wifi = true)))
    }

    @Test
    fun satisfiedCellular() {
        assertEquals("cellular", NetworkTypeClassifier.classify(facts(satisfied = true, cellular = true)))
    }

    @Test
    fun satisfiedEthernet() {
        assertEquals("ethernet", NetworkTypeClassifier.classify(facts(satisfied = true, ethernet = true)))
    }

    @Test
    fun satisfiedButUnclassifiedIsOther() {
        assertEquals("other", NetworkTypeClassifier.classify(facts(satisfied = true)))
    }

    @Test
    fun wifiWinsWhenSeveralInterfacesReport() {
        assertEquals(
            "wifi",
            NetworkTypeClassifier.classify(facts(satisfied = true, wifi = true, cellular = true, ethernet = true)),
        )
    }

    @Test
    fun cellularWinsOverEthernetWhenBothReport() {
        assertEquals(
            "cellular",
            NetworkTypeClassifier.classify(facts(satisfied = true, cellular = true, ethernet = true)),
        )
    }
}
