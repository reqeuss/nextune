package com.reqeuss.nextune

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.EnvironmentalReverb
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "nextune/audio_effects"
    private var bassBoost: BassBoost? = null
    private var equalizer: Equalizer? = null
    private var reverb: EnvironmentalReverb? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "setEffect") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val sessionId = call.argument<Int>("sessionId")
                val effect = call.argument<String>("effect") ?: "Normal"
                if (sessionId == null || sessionId <= 0) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    applyAudioEffect(sessionId, effect)
                    result.success(true)
                } catch (e: Exception) {
                    releaseEffects()
                    result.success(false)
                }
            }
    }

    private fun applyAudioEffect(sessionId: Int, effect: String) {
        releaseEffects()
        when (effect) {
            "Bass Boost" -> {
                bassBoost = BassBoost(0, sessionId).apply {
                    setStrength(650)
                    enabled = true
                }
            }
            "BassMax" -> {
                bassBoost = BassBoost(0, sessionId).apply {
                    setStrength(1000)
                    enabled = true
                }
                equalizer = Equalizer(0, sessionId).apply {
                    val range = bandLevelRange
                    for (band in 0 until numberOfBands) {
                        val hz = getCenterFreq(band.toShort()) / 1000
                        val boost = if (hz < 250) range[1].coerceAtMost(900) else 0
                        setBandLevel(band.toShort(), boost.toShort())
                    }
                    enabled = true
                }
            }
            "Slowed + Reverb" -> {
                reverb = EnvironmentalReverb(0, sessionId).apply {
                    reverbLevel = 650
                    roomLevel = -1000
                    enabled = true
                }
            }
        }
    }

    private fun releaseEffects() {
        try { bassBoost?.release() } catch (_: Exception) {}
        try { equalizer?.release() } catch (_: Exception) {}
        try { reverb?.release() } catch (_: Exception) {}
        bassBoost = null
        equalizer = null
        reverb = null
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}
