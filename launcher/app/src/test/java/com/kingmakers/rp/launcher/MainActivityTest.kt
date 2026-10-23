package com.kingmakers.rp.launcher

import android.graphics.Bitmap
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.drawToBitmap
import androidx.test.core.app.ActivityScenario
import com.google.android.material.textfield.TextInputLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowDialog
import org.robolectric.shadows.ShadowLooper
import java.io.File
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
class MainActivityTest {

    @Test
    fun launcherShowsDefaultServerAndChecksTheName() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val list = activity.findViewById<LinearLayout>(R.id.server_list)
                assertEquals(1, list.childCount)
                assertEquals("127.0.0.1:7777", list.getChildAt(0).findViewById<TextView>(R.id.address).text)

                // An invalid name blocks Play with an error
                activity.findViewById<View>(R.id.play).performClick()
                assertEquals(activity.getString(R.string.name_error), activity.findViewById<TextInputLayout>(R.id.name_layout).error)

                // A valid name without the game installed asks for GTA: San Andreas
                activity.findViewById<TextView>(R.id.name).text = "John_Smith"
                activity.findViewById<View>(R.id.play).performClick()
                assertNotNull(ShadowDialog.getLatestDialog())
                ShadowDialog.getLatestDialog().dismiss()

                // Let the text field's label animation finish before capturing
                ShadowLooper.idleMainLooper(1, TimeUnit.SECONDS)
                screenshot(activity.window.decorView)
            }
        }
    }

    private fun screenshot(view: View) {
        val dir = System.getProperty("screenshotDir") ?: return
        File(dir).mkdirs()
        File(dir, "launcher.png").outputStream().use { view.rootView.drawToBitmap().compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
