package com.yuanbao.petcamera

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import androidx.media3.effect.Crop
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.C
import kotlin.math.*
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File

@UnstableApi
class MovieExporter(private val context: Context) {
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    private var timeout: Runnable? = null

    fun cancel() {
        transformer?.cancel()
        finish(null, "导出已取消")
    }

    private fun finish(path: String?, error: String? = null) {
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        val reply = pending ?: return
        pending = null; transformer = null
        if (path != null) reply.success(path)
        else reply.error("MOVIE_EXPORT", error ?: "视频导出失败", null)
    }

    fun export(args: Map<*, *>, result: MethodChannel.Result) {
        if (pending != null) { result.error("BUSY", "正在导出另一段视频", null); return }
        pending = result
        try {
            val output = args["output_path"] as String
            val duration = (args["duration_ms"] as Number).toLong()
            require(duration in 1..40000) { "片段时长超限" }
            val video = args["video_path"] as String?
            val music = args["music_path"] as String?
            val muted = args["mute_original"] as? Boolean ?: false
            val presentation = Presentation.createForWidthAndHeight(540, 960, Presentation.LAYOUT_SCALE_TO_FIT)
            val items = mutableListOf<EditedMediaItem>()
            if (video != null) {
                val segments = args["segments"] as List<*>
                val cropEffects = mutableListOf<androidx.media3.common.Effect>()
                if (args["subject_fill"] == true) {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(video)
                        var width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toDouble()
                        var height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toDouble()
                        val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
                        if (rotation % 180 != 0) { val tmp = width; width = height; height = tmp }
                        val zoom = (args["zoom"] as Number).toDouble()
                        val w = min(width, height * 9 / 16) / zoom; val h = w * 16 / 9
                        val x = ((args["focus_x"] as Number).toDouble() * width - w/2).coerceIn(0.0,width-w)
                        val y = ((args["focus_y"] as Number).toDouble() * height - h/2).coerceIn(0.0,height-h)
                        cropEffects.add(Crop((2*x/width-1).toFloat(),(2*(x+w)/width-1).toFloat(),
                            (1-2*(y+h)/height).toFloat(),(1-2*y/height).toFloat()))
                    } finally { retriever.release() }
                }
                cropEffects.add(presentation)
                val overlayPath = args["overlay_path"] as String?
                if (overlayPath != null) {
                    val bitmap = BitmapFactory.decodeFile(overlayPath)
                        ?: throw IllegalArgumentException("字幕图层读取失败")
                    cropEffects.add(OverlayEffect(listOf<androidx.media3.effect.TextureOverlay>(BitmapOverlay.createStaticBitmapOverlay(bitmap))))
                }
                for (row in segments) {
                    val segment = row as Map<*,*>
                    val start = (segment["start_ms"] as Number).toLong()
                    val end = (segment["end_ms"] as Number).toLong()
                    val speed = (segment["speed"] as Number).toFloat()
                    require(end>start && speed in listOf(.25f,.5f,1f))
                    val media = MediaItem.Builder().setUri(Uri.fromFile(File(video)))
                        .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(start).setEndPositionMs(end).build()).build()
                    items.add(EditedMediaItem.Builder(media).setRemoveAudio(muted || music != null)
                        .setSpeed(object: SpeedProvider {
                            override fun getSpeed(timeUs: Long): Float = speed
                            override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
                        }).setEffects(Effects(emptyList(), cropEffects)).build())
                }
            } else {
                val slides = args["slides"] as List<*>
                require(slides.isNotEmpty() && slides.size <= 8)
                val slideMs = (args["seconds_per_slide"] as Number).toLong() * 1000
                for (path in slides) {
                    val media = MediaItem.Builder().setUri(Uri.fromFile(File(path as String)))
                        .setImageDurationMs(slideMs).build()
                    items.add(EditedMediaItem.Builder(media).setFrameRate(24)
                        .setEffects(Effects(emptyList(), listOf(presentation))).build())
                }
            }
            val sequence = if (video != null && !muted && music == null)
                EditedMediaItemSequence.withAudioAndVideoFrom(items)
                else EditedMediaItemSequence.withVideoFrom(items)
            val sequences = mutableListOf(sequence)
            if (music != null) {
                val audio = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(music)))).build()
                sequences.add(EditedMediaItemSequence.withAudioFrom(listOf(audio)).buildUpon().setIsLooping(true).build())
            }
            val composition = Composition.Builder(sequences).build()
            val encoder = Transformer.Builder(context).setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) { finish(output) }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        finish(null, exportException.localizedMessage)
                    }
                }).build()
            transformer = encoder
            timeout = Runnable { encoder.cancel(); finish(null, "导出超时，请缩短片段后重试") }
            handler.postDelayed(timeout!!, 150000)
            encoder.start(composition, output)
        } catch (e: Exception) {
            transformer?.cancel()
            finish(null, e.localizedMessage)
        }
    }
    fun analyze(args: Map<*,*>, result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < 27) {
            result.error("ANALYZE", "此系统不支持限尺寸抽帧，请播放后手动标记", null); return
        }
        Thread {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(args["video_path"] as String)
                val start = (args["start_ms"] as Number).toLong()
                val duration = (args["duration_ms"] as Number).toLong().coerceIn(1,30000)
                val fx=(args["focus_x"] as Number).toDouble(); val fy=(args["focus_y"] as Number).toDouble()
                var previous: DoubleArray? = null
                val samples = mutableListOf<Map<String,Any>>()
                for (i in 0 until 40) {
                    val time = start + ((i+.5)*duration/40).toLong()
                    val frame = retriever.getScaledFrameAtTime(time*1000,MediaMetadataRetriever.OPTION_CLOSEST,128,128) ?: continue
                    val w=max(1,frame.width/2);val h=max(1,frame.height/2)
                    val left=(fx*frame.width-w/2).toInt().coerceIn(0,frame.width-w)
                    val top=(fy*frame.height-h/2).toInt().coerceIn(0,frame.height-h)
                    val roi=Bitmap.createBitmap(frame,left,top,w,h)
                    val tiny=Bitmap.createScaledBitmap(roi,64,64,true)
                    val pixels=IntArray(4096);tiny.getPixels(pixels,0,64,0,0,64,64)
                    val luma=DoubleArray(4096);var mean=0.0;var motion=0.0;var sharp=0.0
                    for (p in pixels.indices) {
                        val c=pixels[p];luma[p]=((c shr 16) and 255)*.299+((c shr 8) and 255)*.587+(c and 255)*.114
                        mean+=luma[p];previous?.let {motion+=abs(luma[p]-it[p])}
                    }
                    for(y in 1..62)for(x in 1..62){val p=y*64+x;sharp+=abs(4*luma[p]-luma[p-1]-luma[p+1]-luma[p-64]-luma[p+64])}
                    samples.add(mapOf("time_ms" to time,"motion" to motion/4096,"sharpness" to sharp/3844,"brightness" to mean/4096))
                    previous=luma
                    tiny.recycle();if(roi!==tiny)roi.recycle();if(frame!==roi && frame!==tiny)frame.recycle()
                }
                handler.post { result.success(samples) }
            } catch(e:Exception) {handler.post{result.error("ANALYZE",e.localizedMessage,null)}}
            finally {retriever.release()}
        }.start()
    }

}
