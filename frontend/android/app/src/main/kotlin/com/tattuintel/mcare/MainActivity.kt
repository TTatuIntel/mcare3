package com.tattuintel.mcare

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createEmergencyNotificationChannel()
    }

    private fun createEmergencyNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            "sos_emergency",
            "SOS and critical alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Urgent mCare safety and clinical alerts"
            enableVibration(true)
            setShowBadge(true)
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }
}
