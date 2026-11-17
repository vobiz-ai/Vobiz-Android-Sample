package com.example.vobiz_demo

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's one Flutter engine. It runs the SIP connection and the UI
 * together, and outlives MainActivity.
 *
 * A Vobiz push starts it headless when the app is closed ([CallPushReceiver]),
 * so the Dart side shows the call screen and signs in while the phone is still
 * ringing. Accept then opens MainActivity on this same engine: no second
 * engine, no second SIP connection, and no Dart background handlers.
 *
 * The method channel `vobiz.demo/call` (Dart: CallPlatform):
 *  - Dart -> Android: ready, appInfo, startCallService, stopCallService
 *  - Android -> Dart: push(data), hangUp()
 */
object CallEngine {
    private const val TAG = "VobizCallEngine"
    const val ENGINE_ID = "vobiz_call_engine"
    const val CHANNEL = "vobiz.demo/call"

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    /** Dart called `ready`: pushes can be delivered straight away. */
    private var dartReady = false

    /** Pushes that arrived before Dart was listening. */
    private val pending = mutableListOf<Map<String, String>>()

    /** The engine, started (running `main()`) if it is not running yet. Main thread only. */
    @JvmStatic
    fun obtain(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)

        val engine = FlutterEngine(app)
        val methods = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        methods.setMethodCallHandler { call, result -> onMethodCall(app, call, result) }
        channel = methods
        dartReady = false
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {
                dartReady = false
            }

            override fun onEngineWillDestroy() {
                FlutterEngineCache.getInstance().remove(ENGINE_ID)
                channel = null
                dartReady = false
            }
        })
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        Log.d(TAG, "Started the call engine")
        return engine
    }

    /** A Vobiz push: hand it to Dart, starting the engine if needed. */
    @JvmStatic
    fun deliverPush(context: Context, data: Map<String, String>) {
        main.post {
            obtain(context)
            val methods = channel
            if (dartReady && methods != null) {
                methods.invokeMethod("push", data)
            } else {
                pending.add(data)
            }
        }
    }

    /** "Hang up" on the ongoing-call notification. */
    @JvmStatic
    fun requestHangUp() {
        main.post { channel?.invokeMethod("hangUp", null) }
    }

    private fun onMethodCall(context: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ready" -> {
                    dartReady = true
                    val queued = pending.toList()
                    pending.clear()
                    result.success(queued)
                }
                "appInfo" -> {
                    val info = context.packageManager.getPackageInfo(context.packageName, 0)
                    result.success(mapOf("packageName" to context.packageName, "versionName" to (info.versionName ?: "")))
                }
                "startCallService" -> {
                    CallService.start(
                        context,
                        call.argument<String>("caller") ?: "",
                        call.argument<Boolean>("outbound") ?: false,
                    )
                    result.success(null)
                }
                "stopCallService" -> {
                    CallService.stop(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException, SecurityException …
            Log.w(TAG, "${call.method} failed", e)
            result.error("call_platform", e.message, null)
        }
    }

    /** Opens the app on this engine (from the ongoing-call notification). */
    fun openAppIntent(context: Context): PendingIntent? {
        val open: Intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        return PendingIntent.getActivity(
            context, 0, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
