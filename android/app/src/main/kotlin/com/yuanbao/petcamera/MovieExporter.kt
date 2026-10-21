package com.yuanbao.petcamera

import android.content.Context
import android.graphics.BitmapFactory
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
                val start = (args["trim_start_ms"] as Number).toLong()
                val media = MediaItem.Builder().setUri(Uri.fromFile(File(video)))
                    .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(start).setEndPositionMs(start + duration).build()).build()
                val effects = mutableListOf<androidx.media3.common.Effect>(presentation)
                val overlayPath = args["overlay_path"] as String?
                if (overlayPath != null) {
                    val bitmap = BitmapFactory.decodeFile(overlayPath)
                        ?: throw IllegalArgumentException("字幕图层读取失败")
                    effects.add(OverlayEffect(listOf<androidx.media3.effect.TextureOverlay>(BitmapOverlay.createStaticBitmapOverlay(bitmap))))
                }
                items.add(EditedMediaItem.Builder(media).setRemoveAudio(muted || music != null)
                    .setEffects(Effects(emptyList(), effects)).build())
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
}
