package ai.keex.flashlights_client

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class KeepAliveService : Service() {

    override fun onCreate() {
        super.onCreate()
        createChannelIfNeeded()

        val note = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Flashlights is running")
            .setContentText("Keeping torch and audio in sync…")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)                        // cannot be swiped away
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE
            )
            .build()

        startForeground(NOTIF_ID, note)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Nothing else to do – we just need to stay alive.
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** Creates the notification channel the first time we start (API 26+). */
    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val chan = NotificationChannel(
                    CHANNEL_ID,
                    "Flashlights – keep-alive",
                    NotificationManager.IMPORTANCE_MIN        // won’t buzz the user
                ).apply {
                    description = "Keeps the Flashlights client alive in the background"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(chan)
            }
        }
    }

    companion object {
        private const val CHANNEL_ID = "flashlights_keepalive"
        private const val NOTIF_ID   = 1

        /** Helper so you can call `KeepAliveService.start(context)` from anywhere. */
        fun start(ctx: Context) {
            val intent = Intent(ctx, KeepAliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        }
    }
}
