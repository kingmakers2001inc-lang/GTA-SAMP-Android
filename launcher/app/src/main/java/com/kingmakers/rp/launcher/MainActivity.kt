package com.kingmakers.rp.launcher

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {

    private lateinit var settings: Settings
    private lateinit var serverList: LinearLayout
    private lateinit var nameLayout: TextInputLayout
    private lateinit var nameField: TextInputEditText
    private lateinit var discordButton: MaterialButton

    private val statuses = mutableMapOf<String, ServerStatus?>()
    private val queried = mutableSetOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        settings = Settings(this)

        serverList = findViewById(R.id.server_list)
        nameLayout = findViewById(R.id.name_layout)
        nameField = findViewById(R.id.name)
        discordButton = findViewById(R.id.discord)

        nameField.setText(settings.playerName)
        nameField.doAfterTextChanged {
            val name = it?.toString().orEmpty()
            settings.playerName = name
            if (RpName.isValid(name)) nameLayout.error = null
        }

        findViewById<MaterialButton>(R.id.refresh).setOnClickListener { refreshNow() }
        findViewById<MaterialButton>(R.id.add_server).setOnClickListener { showAddServer() }
        findViewById<MaterialButton>(R.id.play).setOnClickListener { play() }

        renderServers()
        // Keep the list live while the launcher is on screen
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                while (true) {
                    queryAll()
                    delay(10_000)
                }
            }
        }
    }

    private fun refreshNow() {
        lifecycleScope.launch { queryAll() }
    }

    private suspend fun queryAll() {
        val servers = settings.servers
        val results = withContext(Dispatchers.IO) {
            servers.map { server -> async { server.address to ServerQuery(server.host, server.port).query() } }.awaitAll()
        }
        results.forEach { (address, status) ->
            statuses[address] = status
            queried.add(address)
        }
        renderServers()
    }

    private fun renderServers() {
        serverList.removeAllViews()
        val inflater = LayoutInflater.from(this)
        val selected = selectedServer()

        for (server in settings.servers) {
            val card = inflater.inflate(R.layout.item_server, serverList, false) as MaterialCardView
            val status = statuses[server.address]
            val checked = queried.contains(server.address)

            card.findViewById<TextView>(R.id.server_name).text = status?.hostname?.takeIf { it.isNotBlank() } ?: server.name
            card.findViewById<TextView>(R.id.address).text = server.address
            card.findViewById<TextView>(R.id.players).text = when {
                status != null -> getString(R.string.players, status.players, status.maxPlayers)
                checked -> getString(R.string.offline)
                else -> getString(R.string.checking)
            }
            card.findViewById<TextView>(R.id.ping).text = when {
                status == null -> ""
                status.passworded -> getString(R.string.locked)
                status.pingMs >= 0 -> getString(R.string.ping, status.pingMs.toInt())
                else -> ""
            }
            val dotColor = when {
                status != null -> R.color.online
                checked -> R.color.offline
                else -> R.color.unknown
            }
            card.findViewById<View>(R.id.status).backgroundTintList =
                ColorStateList.valueOf(ContextCompat.getColor(this, dotColor))

            val isSelected = server.address == selected.address
            card.setCardBackgroundColor(ContextCompat.getColor(this, if (isSelected) R.color.surface_selected else R.color.surface))
            card.strokeWidth = if (isSelected) resources.displayMetrics.density.times(2).toInt() else 0
            card.strokeColor = ContextCompat.getColor(this, R.color.gold)

            card.setOnClickListener {
                settings.selected = server.address
                renderServers()
            }
            if (server != settings.defaultServer) {
                card.setOnLongClickListener {
                    confirmRemove(server)
                    true
                }
            }
            serverList.addView(card)
        }

        val discord = statuses[selected.address]?.discord
        discordButton.visibility = if (discord != null) View.VISIBLE else View.GONE
        discordButton.setOnClickListener { discord?.let { openUrl(if (it.startsWith("http")) it else "https://$it") } }
    }

    private fun selectedServer(): Server =
        settings.servers.firstOrNull { it.address == settings.selected } ?: settings.defaultServer

    private fun showAddServer() {
        val input = EditText(this).apply {
            hint = getString(R.string.add_server_hint)
            setSingleLine()
        }
        val padding = (20 * resources.displayMetrics.density).toInt()
        val container = LinearLayout(this).apply {
            setPadding(padding, padding / 2, padding, 0)
            addView(input, LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.add_server_title)
            .setView(container)
            .setPositiveButton(R.string.add) { _, _ ->
                val server = Server.parse(input.text.toString())
                if (server == null) {
                    Toast.makeText(this, R.string.invalid_server, Toast.LENGTH_LONG).show()
                } else {
                    settings.addServer(server)
                    settings.selected = server.address
                    renderServers()
                    refreshNow()
                }
            }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun confirmRemove(server: Server) {
        MaterialAlertDialogBuilder(this)
            .setTitle(getString(R.string.remove_server, server.address))
            .setPositiveButton(R.string.remove) { _, _ ->
                settings.removeServer(server)
                if (settings.selected == server.address) settings.selected = settings.defaultServer.address
                renderServers()
            }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun play() {
        val name = nameField.text?.toString().orEmpty().trim()
        if (!RpName.isValid(name)) {
            nameLayout.error = getString(R.string.name_error)
            nameField.requestFocus()
            return
        }
        val server = selectedServer()

        if (!isGameInstalled()) {
            MaterialAlertDialogBuilder(this)
                .setTitle(R.string.game_missing_title)
                .setMessage(R.string.game_missing)
                .setPositiveButton(R.string.open_play) { _, _ -> openGameStorePage() }
                .setNegativeButton(R.string.cancel, null)
                .show()
            return
        }

        val serverName = statuses[server.address]?.hostname?.takeIf { it.isNotBlank() } ?: server.name
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.game_found_title)
            .setMessage(getString(R.string.game_found, serverName, server.address))
            .setPositiveButton(R.string.ok, null)
            .setNeutralButton(R.string.copy_address) { _, _ ->
                val clipboard = getSystemService(ClipboardManager::class.java)
                clipboard.setPrimaryClip(ClipData.newPlainText("server", server.address))
                Toast.makeText(this, R.string.copied, Toast.LENGTH_SHORT).show()
            }
            .show()
    }

    private fun isGameInstalled(): Boolean = try {
        packageManager.getPackageInfo(GAME_PACKAGE, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun openGameStorePage() {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$GAME_PACKAGE")))
        } catch (e: ActivityNotFoundException) {
            openUrl("https://play.google.com/store/apps/details?id=$GAME_PACKAGE")
        }
    }

    private fun openUrl(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, url, Toast.LENGTH_LONG).show()
        }
    }

    companion object {
        const val GAME_PACKAGE = "com.rockstargames.gtasa"
    }
}
