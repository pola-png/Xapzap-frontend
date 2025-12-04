package com.xapzap.xap

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    private var nativeFactory: NativeAdFactorySimple? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeFactory = NativeAdFactorySimple(this)
        GoogleMobileAdsPlugin.registerNativeAdFactory(flutterEngine, "cardNative", nativeFactory!!)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "cardNative")
        nativeFactory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
