package org.wordpress.mobile.ReactNativeAztec

import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.DisplayMetrics
import androidx.collection.ArrayMap
import com.facebook.react.bridge.UiThreadUtil.runOnUiThread

import com.squareup.picasso.Picasso
import com.squareup.picasso.Target

import org.wordpress.aztec.AztecText
import org.wordpress.aztec.Html
import java.util.*

class PicassoImageLoader(private val context: Context, aztec: ReactAztecText) : Html.ImageGetter {

    private val targets: MutableMap<String, com.squareup.picasso.Target>
    private val aztec: ReactAztecText
    init {
        this.targets = ArrayMap<String, Target>()

        // Picasso keeps a weak reference to targets so we need to attach them to AztecText
        aztec.tag = targets
        this.aztec = aztec
    }

    override fun loadImage(source: String, callbacks: Html.ImageGetter.Callbacks, maxWidth: Int) {
        loadImage(source, callbacks, maxWidth, 0)
    }

    override fun loadImage(source: String, callbacks: Html.ImageGetter.Callbacks, maxWidth: Int, minWidth: Int) {
        val picasso = Picasso.with(context)
        picasso.isLoggingEnabled = true
        val aztec = this.aztec
        val target = object : Target {
            override fun onBitmapLoaded(bitmap: Bitmap?, from: Picasso.LoadedFrom?) {
                bitmap?.density = DisplayMetrics.DENSITY_DEFAULT
                val b = bitmap?.let {
                    Bitmap.createBitmap(bitmap, 0, 0, it.getWidth(), bitmap.getHeight())
                }
                callbacks.onImageLoaded(BitmapDrawable(context.resources, b))
                targets.remove(source)
                Timer().schedule(object : TimerTask() {
                    override fun run() {
                        runOnUiThread(java.lang.Runnable {
//                            aztec.onContentSizeChange()
//                            aztec.refreshText()
                        })
                    }
                }, 1000)
            }

            override fun onBitmapFailed(errorDrawable: Drawable?) {
                callbacks.onImageFailed()
                targets.remove(source)
            }

            override fun onPrepareLoad(placeHolderDrawable: Drawable?) {
                callbacks.onImageLoading(placeHolderDrawable)
            }
        }

        // add a strong reference to the target until it's called or the view gets destroyed
        targets.put(source, target)

        picasso.load(source).resize((maxWidth/2.4).toInt(), (maxWidth/2.4).toInt()).centerInside().onlyScaleDown().into(target)
    }
}