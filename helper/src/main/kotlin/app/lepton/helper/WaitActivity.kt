package app.lepton.helper

import android.os.Bundle
import android.view.WindowInsets
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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
        window.insetsController?.hide(WindowInsets.Type.systemBars())
    }
}

@Composable
private fun Wait(title: String) {
    Column(
        Modifier.fillMaxSize().background(Color(0xFF161E2A)).padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator(Modifier.size(64.dp), color = Color(0xFF1A9FFF))
        Text(title, Modifier.padding(top = 16.dp), color = Color.White, fontSize = 26.sp, textAlign = TextAlign.Center)
    }
}
