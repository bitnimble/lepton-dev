package app.lepton.helper

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Resources
import android.os.Bundle
import android.util.DisplayMetrics
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap

/** Android's home screen: the game's loading screen, behind the game once it starts. */
class LoadingActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val game = game()
        setContent { Wait(game?.label.orEmpty(), game?.icon) }
        hideSystemBars()
    }

    private class Game(val label: String, val icon: ImageBitmap)

    private fun game(): Game? {
        val pkg = activeAppId() ?: return null
        return try {
            val info = packageManager.getApplicationInfo(
                pkg,
                PackageManager.MATCH_DIRECT_BOOT_AWARE or PackageManager.MATCH_DIRECT_BOOT_UNAWARE,
            )
            Game(packageManager.getApplicationLabel(info).toString(), icon(info))
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun icon(info: ApplicationInfo): ImageBitmap {
        val px = (ICON_SIZE.value * resources.displayMetrics.density).toInt()
        val sharp = try {
            packageManager.getResourcesForApplication(info).getDrawableForDensity(info.icon, DisplayMetrics.DENSITY_XXXHIGH, null)
        } catch (e: Resources.NotFoundException) {
            null
        }
        return (sharp ?: packageManager.getApplicationIcon(info)).toBitmap(px, px).asImageBitmap()
    }

    private fun activeAppId(): String? =
        ProcessBuilder("getprop", "lepton.active_app_id").start().inputStream.bufferedReader().use { it.readText().trim() }
            .takeIf { it.isNotEmpty() }
}
