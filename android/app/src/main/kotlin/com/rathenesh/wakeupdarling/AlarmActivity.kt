package com.rathenesh.wakeupdarling

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

class AlarmActivity : AppCompatActivity() {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setShowWhenLocked(true)
        setTurnScreenOn(true)

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        // Fullscreen layout (simple programmatic UI).
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(ContextCompat.getColor(this@AlarmActivity, android.R.color.black))
        }

        val title = TextView(this).apply {
            text = "WakeUpDarling"
            textSize = 26f
            setTextColor(ContextCompat.getColor(this@AlarmActivity, android.R.color.white))
            gravity = Gravity.CENTER
        }

        val subtitle = TextView(this).apply {
            text = "Alarm is ringing"
            textSize = 16f
            setTextColor(ContextCompat.getColor(this@AlarmActivity, android.R.color.white))
            gravity = Gravity.CENTER
        }

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        val snoozeBtn = Button(this).apply {
            text = "Snooze (5 min)"
            setOnClickListener {
                stopAlarm()
                scheduleSnooze()
                finish()
            }
        }

        val stopBtn = Button(this).apply {
            text = "Stop"
            setOnClickListener {
                stopAlarm()
                finish()
            }
        }

        buttons.addView(snoozeBtn)
        buttons.addView(stopBtn)

        root.addView(title)
        root.addView(subtitle)
        root.addView(buttons)

        setContentView(root)

        startForegroundSupport()
        startAlarm()
    }

    private fun startForegroundSupport() {
        val intent = Intent(this, AlarmForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopForegroundSupport() {
        stopService(Intent(this, AlarmForegroundService::class.java))
    }

    private fun startAlarm() {
        try {
            player = MediaPlayer.create(this, R.raw.alarm_sound)?.apply {
                isLooping = true
                start()
            }
        } catch (e: Exception) {
            // If raw resource is missing/invalid, keep UI responsive.
        }

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

        try {
            val pattern = longArrayOf(0, 800, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            // Ignore vibration failures.
        }
    }

    private fun stopAlarm() {
        try {
            player?.stop()
        } catch (e: Exception) {
        }
        try {
            player?.release()
        } catch (e: Exception) {
        }
        player = null

        try {
            vibrator?.cancel()
        } catch (e: Exception) {
        }

        stopForegroundSupport()
    }

    private fun scheduleSnooze() {
        val triggerAt = System.currentTimeMillis() + 5 * 60 * 1000L

        val intent = Intent(this, AlarmActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pending = PendingIntent.getActivity(this, 1001, intent, flags)

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } else {
            @Suppress("DEPRECATION")
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }
}
