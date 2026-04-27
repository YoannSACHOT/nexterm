package com.jixter.claude_terminal

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.jixter.nexterm/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val count = call.argument<Int>("count") ?: 1
                        val status = call.argument<String>("status")
                        val intent = Intent(this, SshKeepAliveService::class.java).apply {
                            action = SshKeepAliveService.ACTION_START
                            putExtra(SshKeepAliveService.EXTRA_SESSION_COUNT, count)
                            if (status != null) {
                                putExtra(SshKeepAliveService.EXTRA_STATUS_TEXT, status)
                            }
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "update" -> {
                        val count = call.argument<Int>("count") ?: 1
                        val status = call.argument<String>("status")
                        val intent = Intent(this, SshKeepAliveService::class.java).apply {
                            action = SshKeepAliveService.ACTION_UPDATE
                            putExtra(SshKeepAliveService.EXTRA_SESSION_COUNT, count)
                            if (status != null) {
                                putExtra(SshKeepAliveService.EXTRA_STATUS_TEXT, status)
                            }
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "stop" -> {
                        val intent = Intent(this, SshKeepAliveService::class.java).apply {
                            action = SshKeepAliveService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
