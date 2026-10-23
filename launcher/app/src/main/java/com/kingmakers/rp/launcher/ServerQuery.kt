package com.kingmakers.rp.launcher

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.random.Random

/** Live server status from the SA-MP / open.mp query protocol (UDP, same port as the game). */
data class ServerStatus(
    val hostname: String,
    val gamemode: String,
    val language: String,
    val players: Int,
    val maxPlayers: Int,
    val passworded: Boolean,
    val pingMs: Long,
    val discord: String?,
)

class ServerQuery(private val host: String, private val port: Int, private val timeoutMs: Int = 2000) {

    /** Returns null when the server doesn't answer. */
    fun query(): ServerStatus? = try {
        val address = InetAddress.getByName(host)
        DatagramSocket().use { socket ->
            socket.soTimeout = timeoutMs
            val ping = ping(socket, address)
            val info = request(socket, address, 'i') ?: return null
            // 'o' is open.mp only; plain SA-MP servers just don't answer it
            val extra = request(socket, address, 'o')
            parseInfo(info, ping, extra?.let(::parseDiscord))
        }
    } catch (e: Exception) {
        null
    }

    private fun ping(socket: DatagramSocket, address: InetAddress): Long {
        val token = Random.nextBytes(4)
        val started = System.nanoTime()
        val response = request(socket, address, 'p', token) ?: return -1
        if (!response.copyOfRange(HEADER_SIZE, HEADER_SIZE + 4).contentEquals(token)) return -1
        return (System.nanoTime() - started) / 1_000_000
    }

    private fun request(socket: DatagramSocket, address: InetAddress, type: Char, extra: ByteArray = ByteArray(0)): ByteArray? {
        val packet = header(address, port, type) + extra
        socket.send(DatagramPacket(packet, packet.size, address, port))
        val buffer = ByteArray(4096)
        val reply = DatagramPacket(buffer, buffer.size)
        // Skip stray replies to other query types
        repeat(3) {
            try {
                socket.receive(reply)
            } catch (e: SocketTimeoutException) {
                return null
            }
            val data = buffer.copyOf(reply.length)
            if (data.size >= HEADER_SIZE && data[HEADER_SIZE - 1] == type.code.toByte()) return data
        }
        return null
    }

    companion object {
        /** "SAMP" + server IPv4 + port + query type */
        const val HEADER_SIZE = 11

        fun header(address: InetAddress, port: Int, type: Char): ByteArray {
            val buffer = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)
            buffer.put("SAMP".toByteArray(Charsets.US_ASCII))
            buffer.put(address.address.copyOf(4))
            buffer.putShort(port.toShort())
            buffer.put(type.code.toByte())
            return buffer.array()
        }

        fun parseInfo(data: ByteArray, pingMs: Long, discord: String?): ServerStatus? = try {
            val buffer = ByteBuffer.wrap(data, HEADER_SIZE, data.size - HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)
            val passworded = buffer.get().toInt() != 0
            val players = buffer.short.toInt() and 0xFFFF
            val maxPlayers = buffer.short.toInt() and 0xFFFF
            ServerStatus(
                hostname = readString(buffer),
                gamemode = readString(buffer),
                language = readString(buffer),
                players = players,
                maxPlayers = maxPlayers,
                passworded = passworded,
                pingMs = pingMs,
                discord = discord,
            )
        } catch (e: Exception) {
            null
        }

        fun parseDiscord(data: ByteArray): String? = try {
            val buffer = ByteBuffer.wrap(data, HEADER_SIZE, data.size - HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)
            readString(buffer).takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        }

        // Server strings are length-prefixed (uint32) and usually Windows-1252
        private fun readString(buffer: ByteBuffer): String {
            val length = buffer.int
            require(length in 0..buffer.remaining())
            val bytes = ByteArray(length)
            buffer.get(bytes)
            return String(bytes, charset("windows-1252"))
        }
    }
}
