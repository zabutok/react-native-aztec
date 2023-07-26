package org.wordpress.mobile.ReactNativeAztec

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues.TAG
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.app.ActivityCompat
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import org.json.JSONObject
import org.wordpress.android.util.AppLog
import org.wordpress.android.util.ImageUtils
import org.wordpress.aztec.AztecAttributes
import org.wordpress.aztec.AztecText
import org.xml.sax.Attributes
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.*
import java.util.concurrent.Callable


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
    private fun permissionsCheck(
        activity: Activity,
        requiredPermissions: List<String>,
        callback: Callable<Void?>
    ) {
        val missingPermissions: MutableList<String> = ArrayList()
        val supportedPermissions: MutableList<String> = ArrayList(requiredPermissions)

        // android 11 introduced scoped storage, and WRITE_EXTERNAL_STORAGE no longer works there
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.Q) {
            supportedPermissions.remove(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
        for (permission in supportedPermissions) {
            val status = ActivityCompat.checkSelfPermission(activity, permission)
            if (status != PackageManager.PERMISSION_GRANTED) {
                missingPermissions.add(permission)
            }
        }
        if (!missingPermissions.isEmpty()) {
            (activity as PermissionAwareActivity).requestPermissions(missingPermissions.toTypedArray<String>(),
                1,
                PermissionListener { requestCode, permissions, grantResults ->
                    if (requestCode == 1) {
                        for (permissionIndex in permissions.indices) {
                            val permission = permissions[permissionIndex]
                            val grantResult = grantResults[permissionIndex]
                            if (grantResult == PackageManager.PERMISSION_DENIED) {
                                return@PermissionListener true
                            }
                        }
                        try {
                            callback.call()
                        } catch (e: java.lang.Exception) {
                            //promise.reject(PickerModule.E_CALLBACK_ERROR, "Unknown error", e)
                        }
                    }
                    true
                })
            return
        }

        // all permissions granted
        try {
            callback.call()
        } catch (e: java.lang.Exception) {
        }
    }
    fun onPhotosMediaOptionSelected() {
        getActivity(context)?.let {
            permissionsCheck(
                it,
                listOf<String>(if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) Manifest.permission.WRITE_EXTERNAL_STORAGE else Manifest.permission.READ_MEDIA_IMAGES),
                Callable<Void?> {
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    intent.addCategory(Intent.CATEGORY_OPENABLE)
                    intent.type = "image/*"

                    try {
                        getActivity(context)?.startActivityForResult(intent, REQUEST_MEDIA_PHOTO)
                    } catch (exception: ActivityNotFoundException) {
                        AppLog.e(AppLog.T.EDITOR, exception.message)
                    }
                    null
                })
        }
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
                    try {
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
                    } catch (exception: Exception) {
                        AppLog.e(AppLog.T.EDITOR, exception.message)
                    }
                    //aztec.blockFormatter.toggleQuote()
                })

            }
        })
    }
}
