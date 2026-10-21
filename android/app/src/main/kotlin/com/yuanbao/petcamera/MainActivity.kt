package com.yuanbao.petcamera

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var movieExporter: MovieExporter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        movieExporter = MovieExporter(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yuanbao/movie_export")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "export" -> movieExporter!!.export(call.arguments as Map<*, *>, result)
                    "cancel" -> { movieExporter?.cancel(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        movieExporter?.cancel()
        super.onDestroy()
    }
}
