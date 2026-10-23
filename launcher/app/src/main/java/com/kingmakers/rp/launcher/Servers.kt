package com.kingmakers.rp.launcher

import android.content.Context

data class Server(val name: String, val host: String, val port: Int) {
    val address get() = "$host:$port"

    companion object {
        /** Parses "host:port" (port defaults to 7777) */
        fun parse(text: String, name: String = "Custom server"): Server? {
            val trimmed = text.trim()
            if (trimmed.isEmpty() || trimmed.contains(' ')) return null
            val host = trimmed.substringBefore(':')
            val port = if (trimmed.contains(':')) trimmed.substringAfter(':').toIntOrNull() ?: return null else 7777
            if (host.isEmpty() || port !in 1..65535) return null
            return Server(name, host, port)
        }
    }
}

/** Player name, chosen server and user-added servers, kept in SharedPreferences. */
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("launcher", Context.MODE_PRIVATE)

    val defaultServer = Server(BuildConfig.SERVER_NAME, BuildConfig.SERVER_HOST, BuildConfig.SERVER_PORT)

    var playerName: String
        get() = prefs.getString("name", "") ?: ""
        set(value) = prefs.edit().putString("name", value).apply()

    var selected: String
        get() = prefs.getString("selected", defaultServer.address) ?: defaultServer.address
        set(value) = prefs.edit().putString("selected", value).apply()

    val servers: List<Server>
        get() = listOf(defaultServer) + (prefs.getStringSet("custom", emptySet()) ?: emptySet())
            .sorted()
            .mapNotNull { Server.parse(it) }
            .filter { it.address != defaultServer.address }

    fun addServer(server: Server) {
        val custom = (prefs.getStringSet("custom", emptySet()) ?: emptySet()).toMutableSet()
        custom.add(server.address)
        prefs.edit().putStringSet("custom", custom).apply()
    }

    fun removeServer(server: Server) {
        val custom = (prefs.getStringSet("custom", emptySet()) ?: emptySet()).toMutableSet()
        custom.remove(server.address)
        prefs.edit().putStringSet("custom", custom).apply()
    }
}
