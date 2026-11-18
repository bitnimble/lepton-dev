package app.lepton.helper

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent

/** A full-screen spinner with a title, shown while the host sets Android up; the host ends it. */
class WaitActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val title = intent.getStringExtra("title").orEmpty()
        setContent {
            // leaving would show the half-updated app behind
            BackHandler {}
            Wait(title)
        }
        hideSystemBars()
    }
}
