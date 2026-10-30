package com.example.piliplus

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.UUID

class MainActivity : AudioServiceActivity() {
    private var shareChannel: MethodChannel? = null
    private var shareInFlight: String? = null
    private var shareIntentCaptured = false

    private data class SharedText(val id: String, val text: String) {
        fun toPayload(): Map<String, String> = mapOf("id" to id, "text" to text)
    }

    companion object {
        private const val SHARE_CHANNEL = "io.github.ktclat.piliminus/incoming_share"
        private const val SHARE_CAPTURED_STATE = "piliminus.shareIntentCaptured"
        private const val MAX_SHARE_TEXT_LENGTH = 8192
        private const val MAX_PENDING_SHARES = 8
        private val shareProcessId = UUID.randomUUID().toString()

        // Retain only undelivered shares across Activity/engine reattachment.
        // This queue is process memory only; no shared text goes into saved state.
        private val pendingShares = ArrayDeque<SharedText>()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        val share = pendingShares.pollFirst()
                        if (share?.id == shareInFlight) shareInFlight = null
                        result.success(share?.toPayload())
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // A cached engine may already have a Dart listener. A new engine will
        // either buffer this event or return notImplemented; getInitialShare
        // drains the same queue when Dart finishes installing its listener.
        dispatchPendingShare()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        shareInFlight = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun captureShare(source: Intent?, allowCapture: Boolean = true) {
        if (source?.action != Intent.ACTION_SEND) return
        shareIntentCaptured = true
        try {
            val fromHistory = (source.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
            if (!allowCapture || fromHistory || source.type != "text/plain") return
            val raw = source.getCharSequenceExtra(Intent.EXTRA_TEXT) ?: return
            if (raw.length > MAX_SHARE_TEXT_LENGTH) return
            val text = raw.toString().trim()
            if (text.isEmpty() || text.indexOf('\u0000') >= 0) return
            while (pendingShares.size >= MAX_PENDING_SHARES) pendingShares.removeFirst()
            pendingShares.addLast(SharedText(UUID.randomUUID().toString(), text))
        } catch (_: RuntimeException) {
            // Malformed extras are not a reason to crash or open an arbitrary URI.
        } finally {
            // Clear even rejected SEND payloads. VIEW/SEARCH intents are untouched.
            source.replaceExtras(Bundle())
            source.clipData = null
            source.setDataAndType(null, null)
        }
    }

    private fun dispatchPendingShare() {
        val channel = shareChannel ?: return
        if (shareInFlight != null) return
        val share = pendingShares.peekFirst() ?: return
        shareInFlight = share.id
        channel.invokeMethod("onShareReceived", share.toPayload(), object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (shareChannel !== channel) return
                pendingShares.removeAll { it.id == share.id }
                if (shareInFlight == share.id) shareInFlight = null
                dispatchPendingShare()
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                if (shareChannel !== channel) return
                if (shareInFlight == share.id) shareInFlight = null
            }

            override fun notImplemented() {
                if (shareChannel !== channel) return
                if (shareInFlight == share.id) shareInFlight = null
            }
        })
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Capture before plugins inspect the launch intent, then remove its body.
        // An in-process Activity/engine reattachment must not replay its launch
        // intent. Only an opaque process ID is saved, never the shared text.
        shareIntentCaptured = savedInstanceState?.getString(SHARE_CAPTURED_STATE) == shareProcessId
        captureShare(intent, allowCapture = !shareIntentCaptured)
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onNewIntent(intent: Intent) {
        captureShare(intent)
        setIntent(intent)
        super.onNewIntent(intent)
        dispatchPendingShare()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        if (shareIntentCaptured) outState.putString(SHARE_CAPTURED_STATE, shareProcessId)
        super.onSaveInstanceState(outState)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }
}
