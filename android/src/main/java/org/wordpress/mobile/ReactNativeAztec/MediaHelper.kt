package org.wordpress.mobile.ReactNativeAztec

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues.TAG
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import androidx.appcompat.content.res.AppCompatResources
import com.facebook.react.bridge.UiThreadUtil
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import org.json.JSONObject
import org.wordpress.android.util.AppLog
import org.wordpress.android.util.ImageUtils
import org.wordpress.android.util.PermissionUtils
import org.wordpress.aztec.AztecAttributes
import org.wordpress.aztec.AztecText
import org.wordpress.aztec.AztecTextFormat
import org.xml.sax.Attributes
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.*


class MediaHelper(private val context: Context, aztec: AztecText, aztecManager: ReactAztecManager) {
    private val MEDIA_CAMERA_PHOTO_PERMISSION_REQUEST_CODE: Int = 1001
    private val MEDIA_CAMERA_VIDEO_PERMISSION_REQUEST_CODE: Int = 1002
    private val MEDIA_PHOTOS_PERMISSION_REQUEST_CODE: Int = 1003
    private val MEDIA_VIDEOS_PERMISSION_REQUEST_CODE: Int = 1004
    private val REQUEST_MEDIA_CAMERA_PHOTO: Int = 2001
    private val IMAGE_PICKER_REQUEST: Int = 61110
    private val REQUEST_MEDIA_CAMERA_VIDEO: Int = 2002
    private val REQUEST_MEDIA_PHOTO: Int = 2003
    private val REQUEST_MEDIA_VIDEO: Int = 2004
    private val REQUEST_CROP = 69
    private var progress = 0
    private lateinit var mediaFile: String
    private lateinit var mediaPath: String
    private val aztec: AztecText
    private lateinit var attrs: AztecAttributes
    private val aztecManager: ReactAztecManager
    init {
        this.aztec = aztec
        this.aztecManager = aztecManager
    }
    private fun getActivity(context: Context?): Activity? {
        if (context == null) {
            return null
        } else if (context is ContextWrapper) {
            return if (context is Activity) {
                context as Activity?
            } else {
                getActivity(context.baseContext)
            }
        }
        return null
    }
    fun onPhotosMediaOptionSelected() {
        if (PermissionUtils.checkAndRequestStoragePermission(getActivity(context), MEDIA_PHOTOS_PERMISSION_REQUEST_CODE)) {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            intent.addCategory(Intent.CATEGORY_OPENABLE)
            intent.type = "image/*"

            try {
                getActivity(context)?.startActivityForResult(intent, REQUEST_MEDIA_PHOTO)
            } catch (exception: ActivityNotFoundException) {
                AppLog.e(AppLog.T.EDITOR, exception.message)
            }
        }
//        if (PermissionUtils.checkAndRequestStoragePermission(getActivity(context), MEDIA_PHOTOS_PERMISSION_REQUEST_CODE)) {
//            val intent = Intent(Intent.ACTION_GET_CONTENT)
//            intent.addCategory(Intent.CATEGORY_OPENABLE)
//            intent.type = "image/*"
//            val mimetypes = arrayOf("image/jpeg", "image/png")
//            intent.putExtra(Intent.EXTRA_MIME_TYPES, mimetypes)
//            try {
//                val chooserIntent = Intent.createChooser(intent, "Pick an image");
//                getActivity(context)?.startActivityForResult(chooserIntent, IMAGE_PICKER_REQUEST);
//                //getActivity(context)?.startActivityForResult(intent, IMAGE_PICKER_REQUEST)
//            } catch (exception: ActivityNotFoundException) {
//                AppLog.e(AppLog.T.EDITOR, exception.message)
//            }
//        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK) {
            when (requestCode) {
                REQUEST_MEDIA_CAMERA_PHOTO -> {
                    // By default, BitmapFactory.decodeFile sets the bitmap's density to the device default so, we need
                    //  to correctly set the input density to 160 ourselves.
                    val options = BitmapFactory.Options()
                    options.inDensity = DisplayMetrics.DENSITY_DEFAULT
                    val bitmap = BitmapFactory.decodeFile(mediaPath, options)
                    Log.d("MediaPath", mediaPath)
                    insertImageAndSimulateUpload(bitmap, mediaPath)
                }
                REQUEST_MEDIA_PHOTO -> {
                    mediaPath = data?.data.toString()
                    val stream = getActivity(context)?.contentResolver?.openInputStream(Uri.parse(mediaPath))
                    // By default, BitmapFactory.decodeFile sets the bitmap's density to the device default so, we need
                    //  to correctly set the input density to 160 ourselves.
                    val options = BitmapFactory.Options()
                    options.inDensity = DisplayMetrics.DENSITY_DEFAULT
                    val bitmap = BitmapFactory.decodeStream(stream, null, options)

                    insertImageAndSimulateUpload(bitmap, mediaPath)
                }
            }
        }
    }

    private fun insertImageAndSimulateUpload(bitmap: Bitmap?, mediaPath: String) {
        val bitmapResized = ImageUtils.getScaledBitmapAtLongestSide(bitmap, aztec.maxImagesWidth)
        val (id, attrs) = generateAttributesForMedia(mediaPath, isVideo = false)
        this.attrs = attrs
        aztec.insertImage(BitmapDrawable(getActivity(context)?.resources, bitmapResized), attrs)
        val file = File(mediaPath)
        insertMediaAndSimulateUpload(id)
        uploadImage(id, bitmapResized, file.name)
    }

    private fun generateAttributesForMedia(mediaPath: String, isVideo: Boolean): Pair<String, AztecAttributes> {
        val id = Random().nextInt(Integer.MAX_VALUE).toString()
        val attrs = AztecAttributes()
        attrs.setValue("src", mediaPath) // Temporary source value.  Replace with URL after uploaded.
        attrs.setValue("id", id)
        attrs.setValue("uploading", "true")

        if (isVideo) {
            attrs.setValue("video", "true")
        }

        return Pair(id, attrs)
    }

    private fun insertMediaAndSimulateUpload(id: String) {
        val predicate = object : AztecText.AttributePredicate {
            override fun matches(attrs: Attributes): Boolean {
                return attrs.getValue("id") == id
            }
        }

        aztec.setOverlay(predicate, 0, ColorDrawable(0x80000000.toInt()), Gravity.FILL)
        aztec.updateElementAttributes(predicate, attrs)

        val progressDrawable = AppCompatResources.getDrawable(context, android.R.drawable.progress_horizontal)!!
        // set the height of the progress bar to 2 (it's in dp since the drawable will be adjusted by the span)
        progressDrawable.setBounds(0, 0, 0, 4)

        aztec.setOverlay(predicate, 1, progressDrawable, Gravity.FILL_HORIZONTAL or Gravity.TOP)
        aztec.updateElementAttributes(predicate, attrs)

        progress = 0

        // simulate an upload delay
        val runnable = Runnable {
            aztec.setOverlayLevel(predicate, 1, progress)
            aztec.updateElementAttributes(predicate, attrs)
            aztec.resetAttributedMediaSpan(predicate)
            progress += 2000

            if (progress >= 10000) {
                if (attrs.hasAttribute("uploading")) {
                    attrs.removeAttribute(attrs.getIndex("uploading"))
                }
                aztec.clearOverlays(predicate)
                if (attrs.hasAttribute("video")) {
                    attrs.removeAttribute(attrs.getIndex("video"))
                    aztec.setOverlay(predicate, 0, AppCompatResources.getDrawable(context, android.R.drawable.ic_media_play), Gravity.CENTER)
                }
                var test = attrs
                aztec.updateElementAttributes(predicate, attrs)
            }
        }

        Handler(Looper.getMainLooper()).post(runnable)
        Handler(Looper.getMainLooper()).postDelayed(runnable, 2000)
        Handler(Looper.getMainLooper()).postDelayed(runnable, 4000)
        Handler(Looper.getMainLooper()).postDelayed(runnable, 6000)
        Handler(Looper.getMainLooper()).postDelayed(runnable, 8000)

        //aztec.refreshText()
    }

    fun uploadImage(id: String, image: Bitmap, filename: String) {
        val predicate = object : AztecText.AttributePredicate {
            override fun matches(attrs: Attributes): Boolean {
                return attrs.getValue("id") == id
            }
        }
        val stream = ByteArrayOutputStream()
        image.compress(Bitmap.CompressFormat.JPEG, 90, stream)
        val byteArray = stream.toByteArray()

        val url = aztecManager.imageUrl
        val headers = Headers.Builder()
        val form = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("story_image[image]", filename, RequestBody.create("image/JPEG".toMediaTypeOrNull(), byteArray))

        aztecManager.headers?.toHashMap()?.forEach { (key, value) ->
            headers.add(key as String, value as String)
        }
        aztecManager.parameters?.toHashMap()?.forEach { (key, value) ->
            form.addFormDataPart("story_image["+ key as String +"]", value as String)
        }
        val request = Request.Builder()
            .url(url)
            .headers(headers.build())
            .post(form.build())
            .build()

        val client = OkHttpClient()
        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "Failed to upload image", e)
            }

            override fun onResponse(call: Call, response: Response) {
                Log.i(TAG, "Image uploaded successfully")
                UiThreadUtil.runOnUiThread(Runnable {
                    val jsonData = response.body?.string()
                    val Jobject = JSONObject(jsonData)
                    var url = Jobject.getString("url")
                    var id = Jobject.getString("id")
                    attrs.setValue("src", url)
                    attrs.setValue("data-image_id", id)
                    attrs.setValue("loading", "true")
                    aztec.updateElementAttributes(predicate, attrs)
                    progress = 10000
                    aztec.setOverlayLevel(predicate, 1, progress)
                    aztec.refreshText()
                    aztec.blockFormatter.toggleQuote()
                    //aztec.blockFormatter.toggleQuote()
                })

            }
        })
    }
}