package com.kingmakers.rp.launcher

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/**
 * Runs the query client against a local UDP responder that builds its replies the same way as
 * open.mp's Query::handleQuery (Server/Components/LegacyNetwork/Query/query.cpp): the first 10
 * request bytes are copied, then the type byte and the payload.
 */
class ServerQueryTest {
    private lateinit var socket: DatagramSocket
    private var answerExtra = true

    @Before
    fun startServer() {
        socket = DatagramSocket(0, InetAddress.getLoopbackAddress())
        thread(isDaemon = true) {
            val buffer = ByteArray(2048)
            while (!socket.isClosed) {
                val packet = DatagramPacket(buffer, buffer.size)
                try {
                    socket.receive(packet)
                } catch (e: Exception) {
                    return@thread
                }
                val request = buffer.copyOf(packet.length)
                val reply = reply(request) ?: continue
                socket.send(DatagramPacket(reply, reply.size, packet.address, packet.port))
            }
        }
    }

    @After
    fun stopServer() = socket.close()

    private fun reply(request: ByteArray): ByteArray? {
        if (request.size < 11 || String(request, 0, 4) != "SAMP") return null
        val out = ByteArrayOutputStream()
        out.write(request, 0, 11)
        when (request[10].toInt().toChar()) {
            'p' -> return if (request.size == 15) request else null
            'i' -> {
                out.write(0)                       // not passworded
                out.write(le16(12))                // players
                out.write(le16(100))               // max players
                out.write(str("Kingmakers RP | Mobile Roleplay"))
                out.write(str("Grand RP v0.1"))
                out.write(str("English"))
            }
            'o' -> {
                if (!answerExtra) return null
                out.write(str("discord.gg/kingmakers"))
                out.write(str(""))
                out.write(str(""))
                out.write(str(""))
            }
            else -> return null
        }
        return out.toByteArray()
    }

    private fun le16(value: Int) = ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(value.toShort()).array()

    private fun str(text: String): ByteArray {
        val bytes = text.toByteArray(Charsets.US_ASCII)
        return ByteBuffer.allocate(4 + bytes.size).order(ByteOrder.LITTLE_ENDIAN).putInt(bytes.size).put(bytes).array()
    }

    @Test
    fun readsServerInfoFromOpenMp() {
        val status = ServerQuery("127.0.0.1", socket.localPort).query()
        assertNotNull(status)
        status!!
        assertEquals("Kingmakers RP | Mobile Roleplay", status.hostname)
        assertEquals("Grand RP v0.1", status.gamemode)
        assertEquals("English", status.language)
        assertEquals(12, status.players)
        assertEquals(100, status.maxPlayers)
        assertFalse(status.passworded)
        assertTrue(status.pingMs >= 0)
        assertEquals("discord.gg/kingmakers", status.discord)
    }

    @Test
    fun plainSampServerWithoutExtraInfo() {
        answerExtra = false
        val status = ServerQuery("127.0.0.1", socket.localPort, timeoutMs = 300).query()
        assertNotNull(status)
        assertNull(status!!.discord)
    }

    @Test
    fun offlineServerReturnsNull() {
        val port = DatagramSocket().use { it.localPort }  // nothing listens here any more
        assertNull(ServerQuery("127.0.0.1", port, timeoutMs = 300).query())
    }

    @Test
    fun headerMatchesSampFormat() {
        val header = ServerQuery.header(InetAddress.getByName("203.0.113.5"), 7777, 'i')
        assertEquals("SAMP", String(header, 0, 4))
        assertEquals(listOf(203, 0, 113, 5), header.slice(4..7).map { it.toInt() and 0xFF })
        assertEquals(7777, (header[8].toInt() and 0xFF) or ((header[9].toInt() and 0xFF) shl 8))
        assertEquals('i'.code.toByte(), header[10])
    }

    @Test
    fun truncatedReplyIsRejected() {
        val bad = ServerQuery.header(InetAddress.getLoopbackAddress(), 7777, 'i') + byteArrayOf(0, 5)
        assertNull(ServerQuery.parseInfo(bad, 10, null))
    }
}
