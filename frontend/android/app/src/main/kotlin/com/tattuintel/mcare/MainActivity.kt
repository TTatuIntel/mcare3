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
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val emergency = NotificationChannel(
            "sos_emergency",
            "SOS and critical alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Urgent mCare safety and clinical alerts"
            enableVibration(true)
            setShowBadge(true)
        }
        val updates = NotificationChannel(
            "mcare_updates",
            "Care updates",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Appointments, medication, messages, reports, and account updates"
            enableVibration(false)
            setShowBadge(true)
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannels(listOf(emergency, updates))
    }
}
