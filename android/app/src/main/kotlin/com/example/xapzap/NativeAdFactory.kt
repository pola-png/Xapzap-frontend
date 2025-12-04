package com.xapzap.xap

import android.content.Context
import android.graphics.Typeface
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class NativeAdFactorySimple(private val context: Context) : GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(nativeAd: NativeAd, customOptions: MutableMap<String, Any>?): NativeAdView {
        val adView = NativeAdView(context)

        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val headlineView = TextView(context).apply {
            text = nativeAd.headline ?: ""
            typeface = Typeface.DEFAULT_BOLD
            textSize = 16f
        }

        val bodyView = TextView(context).apply {
            visibility = if (nativeAd.body != null) View.VISIBLE else View.GONE
            text = nativeAd.body ?: ""
            textSize = 14f
        }

        val ctaButton = Button(context).apply {
            text = nativeAd.callToAction ?: "Learn more"
            isAllCaps = false
        }

        container.addView(headlineView)
        container.addView(bodyView)
        container.addView(ctaButton)

        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.callToActionView = ctaButton
        adView.addView(container)

        adView.setNativeAd(nativeAd)
        return adView
    }
}
