package dev.sparkison.mpv

import android.content.Context
import android.view.SurfaceHolder
import android.view.SurfaceView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.EventDispatcher
import dev.jdtech.mpv.MPVLib
import java.util.concurrent.Executors

class MpvPlayerView(context: Context) : SurfaceView(context), SurfaceHolder.Callback,
    MPVLib.EventObserver, MPVLib.LogObserver {

    private var initialized = false
    private var destroying = false
    private var uri: String? = null
    private var userAgent: String? = null
    private var isPaused = false
    private var pendingSeek: Double = -1.0
    private var startPosition: Double = 0.0

    companion object {
        private val destroyExecutor = Executors.newSingleThreadExecutor()
    }

    init {
        holder.addCallback(this)
    }

    fun setUri(value: String?) {
        uri = value
        if (initialized && value != null) {
            loadFile(value)
        }
    }

    fun setUserAgent(value: String?) {
        userAgent = value
        if (initialized && value != null) {
            MPVLib.setPropertyString("user-agent", value)
        }
    }

    fun setPaused(value: Boolean) {
        isPaused = value
        if (initialized) {
            MPVLib.setPropertyBoolean("pause", value)
        }
    }

    fun setStartPosition(seconds: Double) {
        startPosition = seconds
        if (seconds > 0) {
            pendingSeek = seconds
        }
    }

    fun seekTo(seconds: Double) {
        if (!initialized || seconds < 0) return
        MPVLib.command(arrayOf("seek", seconds.toString(), "absolute"))
    }

    fun seekRelative(seconds: Double) {
        if (!initialized) return
        MPVLib.command(arrayOf("seek", seconds.toString(), "relative"))
    }

    fun setAudioTrack(trackId: Int) {
        if (!initialized) return
        if (trackId < 0) {
            MPVLib.setPropertyString("aid", "no")
        } else {
            MPVLib.setPropertyInt("aid", trackId)
        }
    }

    fun setSubtitleTrack(trackId: Int) {
        if (!initialized) return
        if (trackId < 0) {
            MPVLib.setPropertyString("sid", "no")
        } else {
            MPVLib.setPropertyInt("sid", trackId)
        }
    }

    fun stop() {
        if (initialized && !destroying) {
            try {
                MPVLib.command(arrayOf("stop"))
            } catch (_: Exception) { }
        }
    }

    fun destroy() {
        if (!initialized || destroying) return
        destroying = true
        initialized = false
        destroyExecutor.execute {
            try {
                MPVLib.removeObserver(this)
                MPVLib.command(arrayOf("stop"))
                Thread.sleep(50)
                MPVLib.destroy()
            } catch (_: Exception) { }
        }
    }

    private fun initMpv() {
        if (initialized) return

        MPVLib.create(context)

        // Core options (must be set before init)
        MPVLib.setOptionString("vo", "gpu")
        MPVLib.setOptionString("gpu-context", "android")
        MPVLib.setOptionString("hwdec", "mediacodec-copy")
        MPVLib.setOptionString("ao", "audiotrack")
        MPVLib.setOptionString("input-default-bindings", "yes")
        MPVLib.setOptionString("demuxer-max-bytes", "150MiB")
        MPVLib.setOptionString("demuxer-max-back-bytes", "75MiB")
        MPVLib.setOptionString("cache", "yes")
        MPVLib.setOptionString("cache-secs", "120")
        MPVLib.setOptionString("network-timeout", "30")
        MPVLib.setOptionString("keep-open", "yes")
        MPVLib.setOptionString("profile", "fast")
        MPVLib.setOptionString("terminal", "no")
        MPVLib.setOptionString("msg-level", "all=warn")
        MPVLib.setOptionString("tls-verify", "no")
        MPVLib.setOptionString("ytdl", "no")

        // Apply user agent if set
        userAgent?.let {
            MPVLib.setOptionString("user-agent", it)
        }

        // Initialize mpv
        MPVLib.init()

        // Observe properties for events
        MPVLib.addObserver(this)
        MPVLib.observeProperty("time-pos", MPVLib.MPV_FORMAT_DOUBLE)
        MPVLib.observeProperty("duration", MPVLib.MPV_FORMAT_DOUBLE)
        MPVLib.observeProperty("pause", MPVLib.MPV_FORMAT_FLAG)
        MPVLib.observeProperty("paused-for-cache", MPVLib.MPV_FORMAT_FLAG)
        MPVLib.observeProperty("track-list/count", MPVLib.MPV_FORMAT_INT64)
        MPVLib.observeProperty("eof-reached", MPVLib.MPV_FORMAT_FLAG)

        initialized = true

        // Attach surface
        MPVLib.attachSurface(holder.surface)

        // Load pending URI
        uri?.let { loadFile(it) }
    }

    private fun loadFile(url: String) {
        MPVLib.command(arrayOf("loadfile", url))
    }

    private fun sendEvent(eventName: String, params: WritableMap) {
        val reactContext = context as? ReactContext ?: return
        val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
        val dispatcher: EventDispatcher? = UIManagerHelper.getEventDispatcherForReactTag(reactContext, id)
        dispatcher?.dispatchEvent(
            object : com.facebook.react.uimanager.events.Event<Nothing>(surfaceId, id) {
                override fun getEventName(): String = eventName
                override fun getEventData(): WritableMap = params
            }
        )
    }

    // SurfaceHolder.Callback
    override fun surfaceCreated(holder: SurfaceHolder) {
        initMpv()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (initialized && !destroying) {
            MPVLib.setPropertyString("android-surface-size", "${width}x${height}")
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        if (initialized && !destroying) {
            MPVLib.detachSurface()
        }
    }

    // MPVLib.EventObserver
    override fun eventProperty(property: String) {
        // string property change — not used
    }

    override fun eventProperty(property: String, value: Long) {
        if (destroying) return
        when (property) {
            "track-list/count" -> emitTrackInfo()
        }
    }

    override fun eventProperty(property: String, value: Boolean) {
        if (destroying) return
        when (property) {
            "pause" -> {
                // not used — we drive pause from JS
            }
            "paused-for-cache" -> {
                val params = Arguments.createMap()
                params.putBoolean("isBuffering", value)
                sendEvent("onMpvBuffer", params)
            }
            "eof-reached" -> {
                if (value) {
                    sendEvent("onMpvEnd", Arguments.createMap())
                }
            }
        }
    }

    override fun eventProperty(property: String, value: Double) {
        if (destroying) return
        when (property) {
            "time-pos" -> {
                val params = Arguments.createMap()
                params.putDouble("currentTime", value)
                params.putDouble("duration", try { MPVLib.getPropertyDouble("duration") ?: 0.0 } catch (_: Exception) { 0.0 })
                sendEvent("onMpvProgress", params)
            }
            "duration" -> {
                val params = Arguments.createMap()
                params.putDouble("duration", value)
                sendEvent("onMpvLoad", params)
            }
        }
    }

    override fun eventProperty(property: String, value: String) {
        // string property change
    }

    override fun event(eventId: Int) {
        if (destroying) return
        when (eventId) {
            MPVLib.MPV_EVENT_FILE_LOADED -> {
                val duration = try { MPVLib.getPropertyDouble("duration") ?: 0.0 } catch (_: Exception) { 0.0 }
                val params = Arguments.createMap()
                params.putDouble("duration", duration)
                putTrackInfoInMap(params)
                sendEvent("onMpvLoad", params)

                // Apply pending pause
                if (isPaused) {
                    MPVLib.setPropertyBoolean("pause", true)
                }

                // Apply pending seek
                if (pendingSeek >= 0) {
                    MPVLib.command(arrayOf("seek", pendingSeek.toString(), "absolute"))
                    pendingSeek = -1.0
                }
            }
            MPVLib.MPV_EVENT_END_FILE -> {
                sendEvent("onMpvEnd", Arguments.createMap())
            }
        }
    }

    // MPVLib.LogObserver
    override fun logMessage(prefix: String, level: Int, text: String) {
        // Log mpv errors for debugging but don't treat them as playback failures.
        // Non-fatal errors (codec warnings, demuxer retries) are common during init.
        if (level <= MPVLib.MPV_LOG_LEVEL_ERROR) {
            android.util.Log.w("MpvPlayerView", "[$prefix] $text")
        }
    }

    private fun emitTrackInfo() {
        val params = Arguments.createMap()
        putTrackInfoInMap(params)
        sendEvent("onMpvTracksChanged", params)
    }

    private fun putTrackInfoInMap(params: WritableMap) {
        val trackCount = try { MPVLib.getPropertyInt("track-list/count") ?: 0 } catch (_: Exception) { 0 }
        val audioTracks = Arguments.createArray()
        val textTracks = Arguments.createArray()

        for (i in 0 until trackCount) {
            val type = try { MPVLib.getPropertyString("track-list/$i/type") } catch (_: Exception) { null } ?: continue
            val id = try { MPVLib.getPropertyInt("track-list/$i/id") } catch (_: Exception) { null } ?: continue
            val title = (try { MPVLib.getPropertyString("track-list/$i/title") } catch (_: Exception) { null }) ?: ""
            val lang = (try { MPVLib.getPropertyString("track-list/$i/lang") } catch (_: Exception) { null }) ?: ""

            val track = Arguments.createMap()
            track.putInt("id", id)
            track.putString("name", title.ifEmpty { lang.ifEmpty { "Track $id" } })
            track.putString("language", lang)

            when (type) {
                "audio" -> audioTracks.pushMap(track)
                "sub" -> textTracks.pushMap(track)
            }
        }

        params.putArray("audioTracks", audioTracks)
        params.putArray("textTracks", textTracks)
    }
}
