import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 品牌字体族名，必须与 ThemeData.fontFamily 保持一致。
const String kBrandFontFamily = 'Noto Sans SC';

/// 思源黑体子集（由 tools/font-subset/subset.js 生成：GB2312 一级字库 +
/// 源码字符，可变字重已按 400/700 固化成静态字体，合计约 2.3 MB）。
const List<String> kBrandFontAssets = <String>[
  'assets/fonts/NotoSansSC-400.ttf',
  'assets/fonts/NotoSansSC-700.ttf',
];

/// 首帧最多等待字体加载的时长。
///
/// 中文字体子集仍有约 2 MB，慢网下若死等会把首屏拖到几十秒。这里只等一小段：
/// - 命中缓存/网络快：字体在首帧前就绪，全站直接用品牌字体；
/// - 超时：先用系统黑体渲染首屏（观感接近），字体继续后台下载，
///   下载完成后新出现/重排的文本自动切换到品牌字体。
const Duration kBrandFontWait = Duration(milliseconds: 800);

/// 把品牌字体注册进 Flutter 字体库（同名字体族，字重取自文件自身的 OS/2）。
Future<void> loadBrandFont() async {
  final FontLoader loader = FontLoader(kBrandFontFamily);
  for (final String asset in kBrandFontAssets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}

/// 启动阶段调用：限时预载品牌字体，超时或失败都不阻塞首屏。
Future<void> preloadBrandFont({Duration timeout = kBrandFontWait}) async {
  try {
    await loadBrandFont().timeout(timeout);
  } catch (e) {
    // 字体加载失败/超时都不应该让 App 起不来，静默降级为系统字体；
    // 加载仍在后台继续，完成后新出现/重排的文本会自动切换到品牌字体。
    debugPrint('[font] 品牌字体首帧前未就绪，先降级系统字体：$e');
  }
}
