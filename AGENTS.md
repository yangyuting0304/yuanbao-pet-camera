# AGENTS.md —— 给 AI 助手的项目指令（Codex / Cursor / 任何 LLM）

> 人类向的完整交接见 [HANDOVER.md](HANDOVER.md)，待办与事故复盘见 [TODO.md](TODO.md)。
> **本文件是自包含的**：换机器、换助手、零上下文，也应该靠它上手。
>
> 沟通语言：**中文**。提交信息：**中文**，首行写清"类型(范围): 一句话结论"。

## 1. 这是什么

Flutter 宠物相机 App「元宝拍拍」（Android 为主 / iOS 次 / Web 演示）。
卖点是**比系统相机好看**：毛色自适应曝光 + 多帧融合降噪 + 毛发质感 + 猫眼增强。
产品已收敛为**只拍猫**（物种恒为 `PetSpecies.cat`，端侧与云端物种识别全部停用）。

- 仓库：`https://github.com/yangyuting0304/yuanbao-pet-camera`（公开，main = 干净基线）
- 技术栈：Flutter 3.44.7 / Dart 3.12.2 · camera 0.12.1 · camera_avfoundation 0.10.3+1 ·
  tflite_flutter 0.12.1 · package:image · riverpod
- 测试：254 个（`flutter test -j 1` 全过）

## 2. 上手命令

```bash
git clone https://github.com/yangyuting0304/yuanbao-pet-camera.git
cd yuanbao-pet-camera
flutter pub get
flutter test -j 1          # 必须 -j 1：并发编译会 OOM（The Dart compiler exited unexpectedly）
```

调滤镜参数**先上离线实验台**（几秒出图 + 量化指标，别等真机）：

```bash
dart run tools/filter_lab/preview.dart <实拍图.jpg> <输出目录> current subject soft flat
```

构建：

- Android APK → 跑项目根 **`build_apk.cmd`**（路径含中文 + F 盘 exFAT 无法 junction，
  脚本会镜像到 `C:\yuanbao_build` 构建后回拷）。**不要绕过它。**
- iOS → 云构建 `codemagic.yaml`（`flutter build ipa`；Windows 本机不能出 ipa）。
  Podfile 补丁在 `pod install` 时生效；`YUANBAO_IOS_PHOTO_CAP=0` 可临时跳过补丁做 A/B。

## 3. 不可违反的红线

### 3.1 内存（90% 的线上事故都源于内存，不是逻辑）

出片链路是**纯 Dart 逐像素处理**，手机内存上限比桌面低一个量级。

1. **绝不 `img.decodeImage` 全尺寸图**。用 `lib/data/image_decode.dart`：
   `decodeRgbaLimited(bytes, maxSide)` / `decodeRgbaToSize(bytes, w, h)`
   （引擎原生解码器 `dart:ui` 的 `instantiateImageCodec` + `targetWidth`，
   iOS 走 ImageIO 缩略解码路径）。全尺寸解 48MP = **192MB RGBA**。
2. **绝不把大像素用普通 List 传给 `compute`**（会复制：3 帧 3000px = 81MB）。
   用 `TransferableTypedData` 零拷贝（它在 **`dart:isolate`**，不在 `flutter/services`）。
3. **滤镜平面数要算着来**：`pet_filter.dart` 的 `apply` 同时驻留约 6 张像素平面。

### 3.2 isolate 边界

- `dart:ui` 的解码 API **只能在 root isolate 调** → 限尺寸解码必须在主 isolate 做完，
  再把像素交给 isolate（`PetFilter.withRgba` / `FusionPickRequest.preDecoded`）。
- 改任何 record 结构（`PetFilterRequest` / `FusionPickRequest` / `PetCoatRequest`）
  **必须同步改所有构造点**：`dart analyze` 可能不报，`flutter test` 才会暴露。

### 3.3 代码结构

- `lib/app/pages.dart` 是宿主 library，页面文件都是 `part of 'pages.dart'`：
  - import 加在 `pages.dart`，**不是**页面文件里；
  - part 之间私有符号互相可见，命名冲突直接编译失败；
  - `settings_page.dart` / `camera_page.dart` 里的顶层函数是**整个 library 共用**的。
- 平台差异用条件导入（`*_io.dart` / `*_web.dart` / `*_stub.dart`），不要在业务代码里
  写 `Platform.isIOS` 分支（除非确实是平台能力差异）。

### 3.4 画质红线（已写进 `test/pet_filter_sharpness_test.dart`，别退回去）

- 全图锐度比（滤镜后拉普拉斯方差 ÷ 原图拉普拉斯方差）**≤ 1.30**
  —— 修复前是 **1.99**（锐度翻倍），用户评价"还不如原相机"；
- 高频背景区锐度比 **≤ 1.05**（瓷砖/地板类背景不能被放大成"砂纸"）；
- 主体区锐度比 **≥ 0.95**（不许为求稳而磨糊猫毛）；
- 极端清晰度下单像素改动 **≤ 24**（软限幅生效）。

### 3.5 iOS 平台差异（照抄表里的结论，别重新推导）

| 差异 | 处理 | 原因 |
|------|------|------|
| 会话释放慢 | 切模式先 dispose + **800ms** 延迟（Android 250ms） | 过早 initialize 抢不到相机 |
| 端侧推理 | `pet_detector_io.isAvailable` 在 iOS 返回 false（编译期开关 `IOS_TFLITE_ENABLED` 留后路） | tflite_flutter 在 iOS 上是 native 崩溃 |
| 照片输出尺寸 | `ios/Podfile` 补丁压到 12MP（`YUANBAO_IOS_PHOTO_CAP=0` 可跳过） | `ResolutionPreset` 改不了 `activeFormat`，否则 48MP |
| 新会话未稳 | `_cameraSettleUntil` 静默期 1.2s（Android 0.3s） | 期间 `takePicture` 会崩 |
| 并发拍照 | `_photoInFlight` 互斥 | `AVCapturePhotoOutput` 不支持并发拍照 |
| iOS 不自动抓帧 | 毛色分析由用户手动触发 | 自动抓帧本身也是一次 takePicture |

## 4. 关键文件地图

```
lib/app/pages.dart            宿主 library（所有 import 在这）
lib/app/camera_page.dart      相机页：取景/快门/连拍/滤镜编排
lib/data/pet_capture_profile.dart  参数中枢（物种/毛色/场景/风格 → 相机+滤镜参数）
lib/data/pet_filter.dart      滤镜内核：逐像素、软限幅、色度降噪
lib/data/frame_fusion.dart    多帧对齐 + 抗离群平均（降噪主力）
lib/data/image_decode.dart    限尺寸解码（原生解码器）
lib/data/shot_diagnostics.dart 拍照流程落盘日志（iOS 闪退定位）
lib/data/app_env.dart         编译期开关（dart-define）
ios/Podfile                   iOS 照片输出上限补丁
tools/filter_lab/preview.dart 离线滤镜实验台
```

拍照链路（每环都有 `shot_diagnostics.dart` 埋点）：
`快门门禁(互斥+静默期) → 连拍 → 融合(选帧+对齐+抗离群) → 滤镜 → 比例合成 → 落盘/相册/上传`

## 5. 排障手册

| 症状 | 先看 |
|------|------|
| iOS 闪退（native，拿不到控制台日志） | 设置 →「拍照诊断日志」→ 最后一条就是崩的位置 |
| 画质变差 / 锐化过度 | `tools/filter_lab` 的锐度比，对照 §3.4 四条红线 |
| 拍照很卡 | 查有没有人重新引入了全尺寸 `img.decodeImage` |
| 改了 record 结构后编译/测试报错 | 所有构造点都要同步（§3.2） |

**方法论**：能用数字回答的，不要靠肉眼；能复现的，不要靠猜。
每次事故复盘都要留下**证据**（指标、源码行、日志）。

## 6. 未解决 / 已排除（别重复试错）

**未解决**
1. iOS 真机复验：48MP 上限、限尺寸解码、快门闪退三根因（要装新包验证）。
2. iOS 端侧推理（自动追焦）：需要真机崩溃日志才能继续。
3. Android 侧源头限尺寸：没有 Podfile 这种机制，108MP 机型仍可能出巨图。
4. 融合/选帧的限尺寸：已通用，Android 同路径。
5. iOS 动态照片（Live Photo）：当前 iOS 上关闭中。
6. 「实况图」需自写 iOS 原生 channel，排在 Mac 环境就绪后。

**已排除（iOS 端侧推理）**：改 Strip Style 无效；升级 tflite_flutter 到 0.12.1 无效
（两版 `ios/tflite_flutter.podspec` 逐字节相同，仍固定 `TensorFlowLiteSwift 2.12.0`）；
Google 官方 `litert` 包在 pub.dev **404**，社区替代品体量不足以替换生产依赖。

## 7. 提交与协作

- `git add <精确路径>`，**不要 `git add -A`**（会把临时提交信息文件带进提交）。
- 多行中文提交信息必须用 `git commit -F <文件>`（PowerShell 会把 `-m "…"` 拆参数）。
- **APK 不入库**（`.gitignore` 含 `dist/*.apk`）：该仓库历史曾因二进制入库膨胀到 1.76GB。
- 用户实拍照片放 `.filter_lab/`（已 gitignore），**不要提交**。
- `flutter test` 记得 `-j 1`。
