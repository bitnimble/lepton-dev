package app.lepton.helper

import android.app.Activity
import android.view.WindowInsets
import androidx.compose.foundation.Image
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
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

internal val ICON_SIZE = 128.dp

@Composable
internal fun Wait(title: String, icon: ImageBitmap? = null) {
    Column(
        Modifier.fillMaxSize().background(Color(0xFF161E2A)).padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (icon != null) Image(icon, null, Modifier.padding(bottom = 24.dp).size(ICON_SIZE))
        CircularProgressIndicator(Modifier.size(64.dp), color = Color(0xFF1A9FFF))
        Text(title, Modifier.padding(top = 16.dp), color = Color.White, fontSize = 26.sp, textAlign = TextAlign.Center)
    }
}

internal fun Activity.hideSystemBars() {
    window.insetsController?.hide(WindowInsets.Type.systemBars())
}
