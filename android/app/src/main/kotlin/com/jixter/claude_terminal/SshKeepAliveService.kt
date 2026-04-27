package com.jixter.claude_terminal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class SshKeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "nexterm_ssh_keepalive"
        const val NOTIFICATION_ID = 4242
        const val ACTION_START = "com.jixter.claude_terminal.START"
        const val ACTION_STOP = "com.jixter.claude_terminal.STOP"
        const val ACTION_UPDATE = "com.jixter.claude_terminal.UPDATE"
        const val EXTRA_SESSION_COUNT = "session_count"
        const val EXTRA_STATUS_TEXT = "status_text"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val count = intent.getIntExtra(EXTRA_SESSION_COUNT, 0)
                val status = intent.getStringExtra(EXTRA_STATUS_TEXT) ?: defaultStatus(count)
                updateNotification(count, status)
                return START_STICKY
            }
            else -> {
                val count = intent?.getIntExtra(EXTRA_SESSION_COUNT, 1) ?: 1
                val status = intent?.getStringExtra(EXTRA_STATUS_TEXT) ?: defaultStatus(count)
                acquireWakeLock()
                startForegroundCompat(buildNotification(count, status))
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Nexterm:SshKeepAlive"
        ).apply {
            setReferenceCounted(false)
            acquire(8L * 60L * 60L * 1000L)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Sessions SSH",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Maintient les sessions SSH actives en arrière-plan"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(count: Int, status: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPi = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val title = if (count <= 1) "Nexterm — session active"
                    else "Nexterm — $count sessions actives"

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(status)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(contentPi)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(count: Int, status: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(count, status))
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun defaultStatus(count: Int): String =
        if (count <= 0) "Connexion en cours..."
        else "Connexion SSH maintenue"
}
