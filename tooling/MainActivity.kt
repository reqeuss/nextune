package com.reqeuss.nextune

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.EnvironmentalReverb
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

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
                val effect = call.argument<String>("effect") ?: "Original"
                val bass = (call.argument<Number>("bass")?.toDouble() ?: 0.0).coerceIn(0.0, 1.0)
                val treble = (call.argument<Number>("treble")?.toDouble() ?: 0.0).coerceIn(0.0, 1.0)
                val room = (call.argument<Number>("reverb")?.toDouble() ?: 0.0).coerceIn(0.0, 1.0)
                if (sessionId == null || sessionId <= 0) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    applyAudioEffect(sessionId, effect, bass, treble, room)
                    result.success(true)
                } catch (_: Exception) {
                    releaseEffects()
                    result.success(false)
                }
            }
    }

    private fun applyAudioEffect(sessionId: Int, effect: String, bass: Double, treble: Double, room: Double) {
        releaseEffects()
        val bassAmount = when (effect) {
            "BassMax" -> 1.0
            "Bass Boost" -> maxOf(bass, 0.65)
            else -> bass
        }
        val trebleAmount = if (effect == "Nightcore") maxOf(treble, 0.2) else treble
        val reverbAmount = if (effect == "Slowed + Reverb" || effect == "Dream") maxOf(room, 0.65) else room

        if (bassAmount > 0.01) {
            bassBoost = BassBoost(0, sessionId).apply {
                setStrength((bassAmount * 1000).roundToInt().toShort())
                enabled = true
            }
        }

        if (bassAmount > 0.01 || trebleAmount > 0.01 || effect == "BassMax" || effect == "Nightcore") {
            equalizer = Equalizer(0, sessionId).apply {
                val range = bandLevelRange
                val minLevel = range[0].toInt()
                val maxLevel = range[1].toInt()
                for (band in 0 until numberOfBands) {
                    val frequency = getCenterFreq(band.toShort()) / 1000
                    val factor = when {
                        frequency < 250 -> bassAmount
                        frequency >= 4000 -> trebleAmount
                        else -> 0.0
                    }
                    val level = (factor * maxLevel).roundToInt().coerceIn(minLevel, maxLevel)
                    setBandLevel(band.toShort(), level.toShort())
                }
                enabled = true
            }
        }

        if (reverbAmount > 0.01) {
            reverb = EnvironmentalReverb(0, sessionId).apply {
                reverbLevel = (-9000 + reverbAmount * 9000).roundToInt().toShort()
                roomLevel = (-9000 + reverbAmount * 8000).roundToInt().toShort()
                decayTime = (500 + reverbAmount * 2500).roundToInt()
                enabled = true
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
