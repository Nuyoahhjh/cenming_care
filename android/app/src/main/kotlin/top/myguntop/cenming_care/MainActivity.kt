package top.myguntop.cenming_care

import android.content.pm.ApplicationInfo
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.webkit.WebView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val isDebuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        WebView.setWebContentsDebuggingEnabled(isDebuggable)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.myguntop.cenming_care/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openLocationSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error(
                            "LOCATION_SETTINGS_FAILED",
                            error.message,
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
