package com.sezra.sahatakip

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Hesap-telefon eslestirmesi icin kalici cihaz kimligi.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foodtakip/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "info") {
                    val id = Settings.Secure.getString(
                        contentResolver, Settings.Secure.ANDROID_ID
                    ) ?: ""
                    val name = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
                    result.success(mapOf("id" to id, "name" to name))
                } else {
                    result.notImplemented()
                }
            }
    }
}
