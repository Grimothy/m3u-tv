package dev.sparkison.mpv

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise

class MpvModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "MpvModule"

    @ReactMethod
    fun isAvailable(promise: Promise) {
        promise.resolve(true)
    }
}
