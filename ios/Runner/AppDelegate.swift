import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let movieExporter = YuanbaoMovieExporter()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "yuanbao/movie_export",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "export", let args = call.arguments as? [String: Any] {
        self.movieExporter.export(args, result: result)
      } else if call.method == "analyze", let args = call.arguments as? [String: Any] {
        self.movieExporter.analyze(args, result: result)
      } else if call.method == "cancel" {
        self.movieExporter.cancel()
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
  }
}

/// Bounded local slideshow/clip export with AVFoundation, no network or model.
private final class YuanbaoMovieExporter {
  private var reply: FlutterResult?
  private var session: AVAssetExportSession?
  private var writer: AVAssetWriter?
  private var cancelled = false
  private var timeout: DispatchWorkItem?
  private let size = CGSize(width: 540, height: 960)

  func cancel() {
    cancelled = true
    session?.cancelExport()
    writer?.cancelWriting()
    finish(error: "导出已取消")
  }

  private func finish(path: String? = nil, error: String? = nil) {
    DispatchQueue.main.async {
      guard let callback = self.reply else { return }
      self.reply = nil
      self.timeout?.cancel(); self.timeout = nil
      self.session = nil; self.writer = nil
      if let path = path { callback(path) }
      else { callback(FlutterError(code: "MOVIE_EXPORT", message: error ?? "视频导出失败", details: nil)) }
    }
  }

  func export(_ args: [String: Any], result: @escaping FlutterResult) {
    guard reply == nil else { result(FlutterError(code: "BUSY", message: "已有视频正在导出", details: nil)); return }
    guard let output = args["output_path"] as? String,
      let durationMs = args["duration_ms"] as? Int, durationMs > 0, durationMs <= 40000 else {
      result(FlutterError(code: "INVALID", message: "片段时长或路径无效", details: nil)); return
    }
    reply = result; cancelled = false
    let deadline = DispatchWorkItem { [weak self] in self?.cancel() }
    timeout = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 150, execute: deadline)
    if let path = args["video_path"] as? String {
      compose(path: path, output: output, args: args)
    } else {
      let slides = args["slides"] as? [String] ?? []
      let seconds = args["seconds_per_slide"] as? Int ?? 3
      guard !slides.isEmpty, slides.count <= 8, (2...4).contains(seconds) else {
        finish(error: "照片数量或时长无效"); return
      }
      let intermediate = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("slides.mov")
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try self.writeSlides(slides, seconds: seconds, url: intermediate) { ok in
            DispatchQueue.main.async {
              if self.cancelled { return }
              if ok { self.compose(path: intermediate.path, output: output, args: args) }
              else { self.finish(error: "照片视频编码失败，请减少照片后重试") }
            }
          }
        } catch { self.finish(error: error.localizedDescription) }
      }
    }
  }

  private func writeSlides(_ paths: [String], seconds: Int, url: URL,
    completion: @escaping (Bool) -> Void) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    self.writer = writer
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)])
    guard writer.canAdd(input) else { throw NSError(domain: "movie", code: 1) }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "movie", code: 2) }
    writer.startSession(atSourceTime: .zero)
    var frame = 0
    let deadline = Date().addingTimeInterval(140)
    for path in paths {
      if cancelled { writer.cancelWriting(); completion(false); return }
      try autoreleasepool {
        guard let image = UIImage(contentsOfFile: path) else { throw NSError(domain: "movie", code: 3) }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
          kCVPixelFormatType_32BGRA, [kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let pixel = buffer else { throw NSError(domain: "movie", code: 4) }
        CVPixelBufferLockBaseAddress(pixel, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: Int(size.width),
          height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
          CVPixelBufferUnlockBaseAddress(pixel, []); throw NSError(domain: "movie", code: 5)
        }
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context); image.draw(in: CGRect(origin: .zero, size: size)); UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for _ in 0..<(seconds * 12) {
          while !input.isReadyForMoreMediaData && writer.status == .writing && !cancelled && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
          }
          guard !cancelled, Date() < deadline, writer.status == .writing,
            adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 12)) else {
            throw writer.error ?? NSError(domain: "movie", code: 6)
          }
          frame += 1
        }
      }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: Int64(frame), timescale: 12))
    writer.finishWriting { completion(writer.status == .completed) }
  }

  private func compose(path: String, output: String, args: [String: Any]) {
    do {
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      guard let source = asset.tracks(withMediaType: .video).first else {
        finish(error: "所选素材没有可用画面"); return
      }
      let duration = CMTime(seconds: Double(args["duration_ms"] as? Int ?? 0) / 1000, preferredTimescale: 600)
      let isClip = args["video_path"] as? String != nil
      let segments = isClip ? (args["segments"] as? [[String: Any]] ?? []) :
        [["start_ms": 0, "end_ms": args["duration_ms"] as? Int ?? 0, "speed": 1.0]]
      guard !segments.isEmpty else { finish(error: "没有可导出的片段"); return }
      let composition = AVMutableComposition()
      guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        finish(error: "无法创建视频轨道"); return
      }
      var position = CMTime.zero
      for segment in segments {
        let start = CMTime(seconds: Double(segment["start_ms"] as? Int ?? 0)/1000, preferredTimescale:600)
        let end = CMTime(seconds: Double(segment["end_ms"] as? Int ?? 0)/1000, preferredTimescale:600)
        let speed = segment["speed"] as? Double ?? 1
        guard [0.25, 0.5, 1.0].contains(speed), CMTimeCompare(end,start)>0,
          asset.duration.isNumeric, CMTimeCompare(end, asset.duration + CMTime(seconds:0.1,preferredTimescale:600))<=0 else {
          finish(error:"片段范围或速度无效"); return
        }
        let sourceDuration = end-start
        let targetDuration = CMTimeMultiplyByFloat64(sourceDuration, multiplier: 1/speed)
        try video.insertTimeRange(CMTimeRange(start:start,duration:sourceDuration),of:source,at:position)
        video.scaleTimeRange(CMTimeRange(start:position,duration:sourceDuration),toDuration:targetDuration)
        position = position+targetDuration
      }
      let sourceRect = CGRect(origin: .zero, size: source.naturalSize).applying(source.preferredTransform).standardized
      guard sourceRect.width > 0, sourceRect.height > 0 else { finish(error: "视频尺寸无效"); return }
      let fill = args["subject_fill"] as? Bool == true
      let zoom = CGFloat(args["zoom"] as? Double ?? 1)
      let cropW = min(sourceRect.width,sourceRect.height*9/16)/zoom
      let cropH = cropW*16/9
      let x = max(0,min(sourceRect.width-cropW,CGFloat(args["focus_x"] as? Double ?? 0.5)*sourceRect.width-cropW/2))
      let y = max(0,min(sourceRect.height-cropH,CGFloat(args["focus_y"] as? Double ?? 0.5)*sourceRect.height-cropH/2))
      let scale = fill ? size.width/cropW : min(size.width/sourceRect.width,size.height/sourceRect.height)
      let tx = fill ? -x*scale : (size.width-sourceRect.width*scale)/2
      let ty = fill ? -y*scale : (size.height-sourceRect.height*scale)/2
      let transform = source.preferredTransform
        .concatenating(CGAffineTransform(translationX:-sourceRect.minX,y:-sourceRect.minY))
        .concatenating(CGAffineTransform(scaleX:scale,y:scale))
        .concatenating(CGAffineTransform(translationX:tx,y:ty))
      let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
      layer.setTransform(transform, at: .zero)
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = CMTimeRange(start: .zero, duration: duration); instruction.layerInstructions = [layer]
      let vc = AVMutableVideoComposition()
      vc.renderSize = size; vc.frameDuration = CMTime(value: 1, timescale: 24); vc.instructions = [instruction]
      if let overlayPath = args["overlay_path"] as? String,
        let overlay = UIImage(contentsOfFile: overlayPath)?.cgImage {
        let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: size)
        let imageLayer = CALayer(); imageLayer.frame = parent.bounds; imageLayer.contents = overlay
        let videoLayer = CALayer(); videoLayer.frame = parent.bounds
        parent.addSublayer(videoLayer); parent.addSublayer(imageLayer)
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
      }
      if let music = args["music_path"] as? String {
        let musicAsset = AVURLAsset(url: URL(fileURLWithPath: music))
        guard let track = musicAsset.tracks(withMediaType: .audio).first,
          musicAsset.duration.isNumeric, CMTimeCompare(musicAsset.duration, .zero) > 0,
          let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
          finish(error: "配乐文件无有效音轨"); return
        }
        var position = CMTime.zero
        while CMTimeCompare(position, duration) < 0 {
          let length = CMTimeMinimum(musicAsset.duration, duration - position)
          try audio.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: position)
          position = position + length
        }
      } else if args["mute_original"] as? Bool != true, let original = asset.tracks(withMediaType: .audio).first,
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        var audioPosition = CMTime.zero
        for segment in segments {
          let begin = CMTime(seconds:Double(segment["start_ms"] as? Int ?? 0)/1000,preferredTimescale:600)
          let end = CMTime(seconds:Double(segment["end_ms"] as? Int ?? 0)/1000,preferredTimescale:600)
          let length = end-begin
          let target = CMTimeMultiplyByFloat64(length,multiplier:1/(segment["speed"] as? Double ?? 1))
          try audio.insertTimeRange(CMTimeRange(start:begin,duration:length),of:original,at:audioPosition)
          audio.scaleTimeRange(CMTimeRange(start:audioPosition,duration:length),toDuration:target)
          audioPosition = audioPosition+target
        }
      }
      guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        finish(error: "系统视频编码器不可用"); return
      }
      session = exporter
      exporter.outputURL = URL(fileURLWithPath: output); exporter.outputFileType = .mp4
      exporter.videoComposition = vc; exporter.shouldOptimizeForNetworkUse = true
      exporter.exportAsynchronously { [weak self] in
        if exporter.status == .completed { self?.finish(path: output) }
        else { self?.finish(error: exporter.error?.localizedDescription ?? "视频导出被中断") }
      }
    } catch { finish(error: error.localizedDescription) }
  }
  func analyze(_ args: [String:Any], result: @escaping FlutterResult) {
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        guard let path=args["video_path"] as? String else {throw NSError(domain:"video",code:1)}
        let asset=AVURLAsset(url:URL(fileURLWithPath:path))
        let generator=AVAssetImageGenerator(asset:asset)
        generator.appliesPreferredTrackTransform=true
        generator.maximumSize=CGSize(width:128,height:128)
        generator.requestedTimeToleranceBefore=CMTime(seconds:0.05,preferredTimescale:600)
        generator.requestedTimeToleranceAfter=CMTime(seconds:0.05,preferredTimescale:600)
        let start=args["start_ms"] as? Int ?? 0
        let duration=min(30000,max(1,args["duration_ms"] as? Int ?? 1))
        let fx=args["focus_x"] as? Double ?? 0.5, fy=args["focus_y"] as? Double ?? 0.5
        var previous:[Double]?=nil
        var samples=[[String:Any]]()
        for i in 0..<40 {
          try autoreleasepool {
            let ms=Double(start)+(Double(i)+0.5)*Double(duration)/40
            let frame=try generator.copyCGImage(at:CMTime(seconds:ms/1000,preferredTimescale:600),actualTime:nil)
            let w=CGFloat(frame.width)/2,h=CGFloat(frame.height)/2
            let x=max(0,min(CGFloat(frame.width)-w,CGFloat(fx)*CGFloat(frame.width)-w/2))
            let y=max(0,min(CGFloat(frame.height)-h,CGFloat(fy)*CGFloat(frame.height)-h/2))
            guard let roi=frame.cropping(to:CGRect(x:x,y:y,width:w,height:h)) else {return}
            var bytes=[UInt8](repeating:0,count:64*64*4)
            try bytes.withUnsafeMutableBytes { buffer in
              guard let context=CGContext(data:buffer.baseAddress,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw NSError(domain:"frame",code:2)}
              context.draw(roi,in:CGRect(x:0,y:0,width:64,height:64))
            }
            var luma=[Double](repeating:0,count:4096),mean=0.0,motion=0.0,sharp=0.0
            for p in 0..<4096 {
              luma[p]=Double(bytes[p*4])*0.299+Double(bytes[p*4+1])*0.587+Double(bytes[p*4+2])*0.114
              mean+=luma[p]; if let prev=previous {motion+=abs(luma[p]-prev[p])}
            }
            for y in 1...62 {for x in 1...62 {let p=y*64+x;sharp+=abs(4*luma[p]-luma[p-1]-luma[p+1]-luma[p-64]-luma[p+64])}}
            samples.append(["time_ms":Int(ms),"motion":motion/4096,"sharpness":sharp/3844,"brightness":mean/4096])
            previous=luma
          }
        }
        DispatchQueue.main.async {result(samples)}
      } catch {DispatchQueue.main.async{result(FlutterError(code:"ANALYZE",message:error.localizedDescription,details:nil))}}
    }
  }

}
