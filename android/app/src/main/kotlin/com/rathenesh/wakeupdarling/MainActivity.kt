package com.rathenesh.wakeupdarling

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		createAlarmChannel()
		maybeStartAlarmActivity(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		maybeStartAlarmActivity(intent)
	}

	override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ultra_alarm")
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"requestDndAccessIfNeeded" -> {
						val manager = getSystemService(NotificationManager::class.java)
						if (manager != null && !manager.isNotificationPolicyAccessGranted) {
							val settingsIntent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
								.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(settingsIntent)
							result.success(false)
						} else {
							result.success(true)
						}
					}

					"openAlarmActivity" -> {
						startActivity(
							Intent(this, AlarmActivity::class.java)
								.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						)
						result.success(true)
					}

					"requestBatteryOptimizationExemption" -> {
						val pm = getSystemService(PowerManager::class.java)
						val pkg = packageName
						if (pm != null && !pm.isIgnoringBatteryOptimizations(pkg)) {
							val intent = Intent(
								Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
								Uri.parse("package:$pkg")
							).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(intent)
							result.success(false)
						} else {
							result.success(true)
						}
					}

					"enableSecureMode" -> {
						window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
						result.success(true)
					}

					"disableSecureMode" -> {
						window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
						result.success(true)
					}

					else -> result.notImplemented()
				}
			}
	}

	private fun createAlarmChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

		val channel = NotificationChannel(
			"alarm_channel",
			"Alarm Channel",
			NotificationManager.IMPORTANCE_HIGH
		)
		channel.setBypassDnd(true)
		channel.enableVibration(true)
		channel.enableLights(true)
		channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC

		val manager = getSystemService(NotificationManager::class.java)
		manager?.createNotificationChannel(channel)
	}

	private fun maybeStartAlarmActivity(intent: Intent?) {
		if (intent == null) return

		// Avoid repeatedly re-launching if the Activity gets re-delivered.
		if (intent.getBooleanExtra("ultra_alarm_handled", false)) return

		val extras = intent.extras ?: return
		val isAlarm = extras.keySet().any { key ->
			val value = extras.get(key)
			value is String && value == "alarm"
		}
		if (!isAlarm) return

		startActivity(
			Intent(this, AlarmActivity::class.java)
				.putExtra("ultra_alarm_handled", true)
				.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		)
	}
}
