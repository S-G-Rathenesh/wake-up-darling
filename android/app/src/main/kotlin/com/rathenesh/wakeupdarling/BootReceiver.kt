package com.rathenesh.wakeupdarling

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Recreates the alarm notification channel (with DND bypass) on device boot
 * so that flutter_local_notifications' own ScheduledNotificationBootReceiver
 * can successfully reschedule alarms into an existing channel.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
		val channel = NotificationChannel(
			"alarm_channel",
			"WakeUpDarling Alarm",
			NotificationManager.IMPORTANCE_HIGH
		)
		channel.setBypassDnd(true)
		channel.enableVibration(true)
		channel.enableLights(true)
		channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC

		val manager = context.getSystemService(NotificationManager::class.java)
		manager?.createNotificationChannel(channel)
	}
}
