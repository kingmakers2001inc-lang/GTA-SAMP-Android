package com.kingmakers.rp.launcher

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NamesAndServersTest {
    @Test
    fun rpNamesFollowTheServerRule() {
        assertTrue(RpName.isValid("John_Smith"))
        assertTrue(RpName.isValid("Ana_Silva"))
        assertFalse(RpName.isValid("john_smith"))
        assertFalse(RpName.isValid("John_smith"))
        assertFalse(RpName.isValid("JohnSmith"))
        assertFalse(RpName.isValid("John_Smith_Jr"))
        assertFalse(RpName.isValid("John_Sm1th"))
        assertFalse(RpName.isValid("Johnathanson_Smithersonson"))
    }

    @Test
    fun serverAddressesParse() {
        assertEquals(Server("Custom server", "203.0.113.5", 7777), Server.parse("203.0.113.5:7777"))
        assertEquals(7777, Server.parse("play.example.com")!!.port)
        assertEquals(8888, Server.parse(" 10.0.0.2:8888 ")!!.port)
        assertNull(Server.parse(""))
        assertNull(Server.parse("1.2.3.4:abc"))
        assertNull(Server.parse("1.2.3.4:70000"))
        assertNull(Server.parse("bad host:7777"))
    }
}
