# 交接文档 · 元宝拍拍（pet_camera）

> 给接手的人（人 or AI）看的一页纸：**这是什么、怎么改、哪些约定不能破、最近发生了什么、怎么验证**。
>
> 细节不在这里：待办与事故复盘见 [TODO.md](TODO.md)，环境搭建见
> [README_setup.md](README_setup.md)，部署见 [DEPLOY.md](DEPLOY.md)，
> 构建见 [README_build.md](README_build.md)。

## 一、30 秒速览

| 项 | 内容 |
|----|------|
| 产品 | Flutter 宠物相机 App「元宝拍拍」——给猫狗拍照，卖点是**比系统相机好看**（毛色自适应曝光 + 多帧融合降噪 + 毛发质感 + 猫眼增强） |
| 平台 | Android（主）/ iOS（次）/ Web（演示） |
| 仓库 | https://github.com/yangyuting0304/yuanbao-pet-camera（公开，main = 干净基线） |
| 技术栈 | Flutter 3.x · camera 0.12.1 · camera_avfoundation 0.10.3+1 · tflite_flutter 0.12.1 · package:image · riverpod |
| 当前状态 | 2026-10-21：产品已收敛为**只拍猫**；iOS 的 48MP 输出失控 / 全尺寸解码 / 快门闪退三根因已修，**待真机复验** |
| 测试 | 245 个单元/契约测试全过（`flutter test -j 1`） |
| 一句话 | **出片链路是纯 Dart 逐像素处理，内存是第一约束**——本项目几乎所有线上事故都源于"在手机上解一张 48MP 图" |

## 二、文件地图（改什么 → 去哪改）

```
lib/
├─ app/
│  ├─ pages.dart              ← 宿主 library：所有 import + part 声明都在这
│  ├─ camera_page.dart        ← 相机页（part of pages.dart）：取景、快门、连拍、滤镜编排
│  ├─ settings_page.dart      ← 设置页（part of）
│  ├─ album_page.dart         ← 相册
│  └─ tokens.dart             ← 品牌常量（AppUi.appName = 元宝拍拍）
├─ data/
│  ├─ pet_capture_profile.dart ← **参数中枢**：物种/毛色/场景/风格 → 相机参数 + 滤镜参数
│  ├─ pet_filter.dart          ← 滤镜内核（逐像素）+ 软限幅 + 色度降噪
│  ├─ frame_fusion.dart        ← 多帧对齐 + 抗离群平均（降噪主力）
│  ├─ burst_selector.dart      ← 清晰度评分（已被 frame_fusion 内部取代，保留算法）
│  ├─ image_decode.dart        ← **限尺寸解码**（原生解码器，见下）
│  ├─ shot_diagnostics.dart    ← 拍照流程落盘日志（iOS 闪退定位用）
│  ├─ pet_detector_io.dart     ← 实时宠物检测（iOS 当前禁用）
│  ├─ photo_storage_io.dart    ← 落盘照片（Documents/captured_photos）
│  └─ app_env.dart             ← 编译期开关（dart-define）
└─ tools/filter_lab/preview.dart ← **离线滤镜实验台**（调参先在这里看）
ios/Podfile                    ← iOS 照片输出上限补丁（12MP）
test/                          ← 245 个测试，按主题分文件
tools/filter_lab/              ← 实验台脚本
```

## 三、架构约定（红线，改代码前先读）

### 3.1 内存是第一约束

手机（尤其 iOS）上的内存上限比桌面低一个量级，而本 App 的出片链路是**纯 Dart 逐像素处理**：

```
takePicture → JPEG 字节 → 原生解码器缩到目标尺寸 → RGBA 平面 → 滤镜逐像素 → JPEG
```

历史事故几乎全在这条链路上。**三条铁律**：

1. **绝不 `img.decodeImage` 全尺寸图**。要用 `image_decode.dart` 的
   `decodeRgbaLimited(bytes, maxSide)` / `decodeRgbaToSize(bytes, w, h)`
   （引擎原生解码器，dart:ui 的 `instantiateImageCodec` + `targetWidth`，
   iOS 走 ImageIO 缩略解码路径）。全尺寸解码 48MP = 192MB RGBA。
2. **绝不把大像素用普通 List 传给 `compute`**。compute 会**复制**参数
   （3 帧 3000px RGBA = 81MB 复制），必须用 `TransferableTypedData` 零拷贝
   （它在 `dart:isolate` 里，不在 `flutter/services`）。
3. **滤镜平面数要算着来**。`pet_filter.dart` 的 `apply` 同时驻留
   luma + blurred + blurSharp + blurMid + 两张色度平面 ≈ 6 × 像素数 字节。

### 3.2 isolate 边界

- `dart:ui` 的解码 API **只能在 root isolate 调用** → 限尺寸解码必须在主 isolate
  做完，再把像素交给 isolate（`PetFilter.withRgba` / `FusionPickRequest.preDecoded`）。
- isolate 里只能用纯 Dart 解码（`package:image`），这正是要避免全尺寸解码的原因。
- 改任何 record 结构（`PetFilterRequest` / `FusionPickRequest` /
  `PetCoatRequest`）**必须同步改所有构造点**——`dart analyze` 可能不报，
  `flutter test` 才会暴露。

### 3.3 pages.dart 的 part 结构

`lib/app/pages.dart` 是宿主 library，页面文件都是 `part of 'pages.dart'`：

- 新增 import 加在 `pages.dart`，**不是**页面文件里；
- 页面文件的私有符号（`_CameraPageState` 等）在 part 之间**互相可见**，
  命名冲突会直接编译失败；
- `settings_page.dart` / `camera_page.dart` 里的顶层函数（如 `_confirmClear`）
  是**整个 library 共用**的，插入代码时别切进别的函数的参数列表。

### 3.4 平台差异

| 差异点 | 处理方式 | 原因 |
|--------|---------|------|
| iOS 相机会话释放慢 | 切模式先 dispose + **800ms** 延迟（Android 250ms） | 过早 initialize 会抢不到相机 |
| iOS 端侧推理 | `pet_detector_io.isAvailable` 返回 false；用编译期开关 `IOS_TFLITE_ENABLED` 留后路 | tflite_flutter 在 iOS 上是 native 崩溃 |
| iOS 照片输出尺寸 | `ios/Podfile` 补丁压到 12MP（逃生开关 `YUANBAO_IOS_PHOTO_CAP=0`） | `ResolutionPreset` 改不了 `activeFormat` |
| iOS 新会话未稳 | `_cameraSettleUntil` 静默期 1.2s | 期间 `takePicture` 会崩 |
| iOS 并发拍照 | `_photoInFlight` 互斥 | AVCapturePhotoOutput 不支持并发 |
| iOS 不自动抓帧 | 毛色分析改由用户手动触发 | 自动抓帧也是一次 takePicture |

### 3.5 画质红线（写进测试了，别退回去）

`test/pet_filter_sharpness_test.dart` 钉死：

- 全图锐度比（滤镜后拉普拉斯方差 ÷ 原图拉普拉斯方差）**≤ 1.30**
  ——修复前是 **1.99**（锐度翻倍），用户评价"还不如原相机"；
- 高频背景区锐度比 **≤ 1.05**（背景是瓷砖/地板时不能被放大成"砂纸"）；
- 主体区锐度比 **≥ 0.95**（不许为了稳而磨糊猫毛）；
- 极端清晰度下单像素改动 **≤ 24**（软限幅生效）。

## 四、拍照链路全景（改任何一步前先看这里）

```
用户按快门
 ├─ 门禁 1：_photoInFlight（与自动抓帧互斥）      ← 并发拍照 = iOS 崩溃
 ├─ 门禁 2：_cameraSettling（iOS 1.2s）            ← 会话未稳 = iOS 崩溃
 ├─ _captureBurst：连拍 N 张（iOS 封顶 3，间隔 150ms）
 │    └─ 每张：takePicture → JPEG 字节（iOS 12MP ≈ 3MB）
 ├─ _fuseFrames
 │    ├─ 主 isolate：原生解码器把每帧缩到 3000px → TransferableTypedData 零拷贝移交
 │    └─ isolate：选最清晰一帧 + 对齐 + 抗离群平均 → JPEG
 ├─ _applyPetFilter
 │    ├─ 主 isolate：原生解码器缩到 3000px（RGBA 27MB）
 │    └─ isolate：逐像素内核（亮度/色度降噪、软限幅锐度、毛发质感、猫眼、泪痕、暗角）
 ├─ _composePhotoToSelectedRatio：原生解码（targetWidth 封顶 3000）+ Canvas 裁切加框
 └─ 落盘 + 存系统相册 + 异步上传 COS
```

每一环都有 `shot_diagnostics.dart` 的埋点（`takePicture.start` / `burst.shot` /
`fuse.start` / `fuse.end` / `filter.end` / `compose.end`）。

## 五、最近的事故（都是"证据驱动"的修复，别推翻）

| 事故 | 根因 | 修法 | 证据 |
|------|------|------|------|
| 锐化过度，用户说"还不如原相机" | 滤镜把锐度**翻倍**（texture 在高频放大，而宠物照背景全是高频纹理） | texture 0.22→0.08、背景底值 0.30→0.08、新增软限幅、锐化与降噪分账 | 锐度比 1.99 → 1.12~1.24 |
| iOS 拍出来是 48MP | `ResolutionPreset` 只改 session preset，**改不了 activeFormat** | `ios/Podfile` 补丁压到 12MP | 读 camera_avfoundation 的 Swift 源码 |
| iOS 拍照模式很卡 / 闪退 | 链路 5 处全尺寸解码（48MP→192MB/张） | 全链路限尺寸解码（原生解码器） | 内存与耗时只跟目标尺寸有关 |
| iOS 第二天才闪退 | 启动回填 200 张历史照片**全量常驻**（200~600MB） | 回填降到 24 张 | 常驻内存模型 |
| iOS 点快门闪退 | ①并发 takePicture ②会话未稳 ③连拍背靠背 + 旧 controller 竞态 | 互斥 + 门闩 + 间隔 + 快照校验 | 真机复现路径 |
| 猫被识别成狗 | MobileNetV2 全类聚合在宠物特写上常判错 | 物种识别整体停用（只拍猫） | — |

**方法论**（比结论更值得继承）：能用数字回答的，不要靠肉眼。
`tools/filter_lab/preview.dart` 是为此造的——把真机实拍图喂进滤镜管线，
几秒出一张对照图 + 锐度比/过冲指标：

```bash
dart run tools/filter_lab/preview.dart <实拍图.jpg> <输出目录> current subject soft flat
```

## 六、怎么验证一次改动

1. **单元/契约测试**：`flutter test -j 1`（必须 `-j 1`，并发编译会 OOM）。
   245 个测试，重点是 `pet_filter_sharpness_test.dart`（画质红线）、
   `image_decode_test.dart`（限尺寸解码）、`frame_fusion_predecoded_test.dart`
   （融合两条通路画质相当）。
2. **Android 真机**：走项目根 `build_apk.cmd`（见下）。
3. **iOS 真机**：云构建（`codemagic.yaml` → `flutter build ipa`，
   Podfile 补丁在 `pod install` 时生效）。装机后按这个清单过一遍：
   - 成片分辨率应约 **4032×3024**（不是 8064×6048）；
   - 切宠物模式后**等 1 秒多**再按快门（会话未稳会拦下并提示）；
   - 连拍 3~5 张不闪退；
   - 进宠物模式不卡。
4. **闪退了怎么办**：设置 → 「拍照诊断日志」→ 最后一条就是崩的位置
   （native 崩溃拿不到控制台日志，只能靠它）。把内容发给开发即可。
5. **改了滤镜参数**：先在 `tools/filter_lab` 里看锐度比，别直接上真机。

## 七、构建与发布

| 目标 | 命令 / 位置 | 注意 |
|------|-------------|------|
| Android APK | 项目根 **`build_apk.cmd`** | 路径含中文 + F 盘 exFAT 无法 junction → 脚本会镜像到 `C:\yuanbao_build` 构建后回拷；**不要绕过它** |
| iOS 包 | `codemagic.yaml`（云构建，`flutter build ipa`） | Podfile 补丁在 `pod install` 时自动生效；可用环境变量 `YUANBAO_IOS_PHOTO_CAP=0` 临时跳过补丁做 A/B |
| APK 分发 | **不入库**（`.gitignore` 里有 `dist/*.apk`） | 该仓库历史上曾因二进制入库膨胀到 1.76GB；dist 只留 README |

**提交规范**：`git add <精确路径>`，不要 `git add -A`（会把临时提交信息文件一起带进去）。

## 八、踩坑速查（都实际踩过）

**工具**
- `write_to_file` 的 `filePath` 必须放在 `content` **之前**，否则报
  `missing required argument filePath`；长 `content` 会被截断 →
  大文件用 `replace_in_file` 分段追加。
- `flutter test` 并发编译会 OOM（`The Dart compiler exited unexpectedly`）→ 用 `-j 1`。
- `dart analyze` 对 record 结构变更可能不报错，`flutter test` 才会暴露。

**Git**
- PowerShell 里 `git commit -m "多行中文…"` 会被引号拆成多参数 → **必须**
  `git commit -F <文件>`，且 `git add` 用精确路径。
- `git push` 报 `! [rejected] main -> main (fetch first)` **不是网络问题**，
  是远端有本地没有的提交 → 先 `git fetch origin` 看差异再 rebase。
- 推大文件要 `git -c http.postBuffer=524288000`（临时覆盖，不改配置）。
- 本机对 github.com 直连有时 `schannel SSL handshake failed`；
  `gitclone.com` 镜像可 clone，`codeload.github.com` 可下 zip。

**Flutter / iOS**
- iOS 相机：dispose 后**必须等**（800ms）再 initialize，否则抢不到会话。
- `ResolutionPreset` 在 iOS 上**改不了输出尺寸**，别再指望它限分辨率。
- `AVCapturePhotoOutput` **不支持并发拍照**。
- native 崩溃会带走所有 Dart 日志 → 关键流程要落盘（`shot_diagnostics.dart`）。

## 九、还没解决 / 下一步

1. **iOS 真机复验**（最高优先）：48MP 上限、限尺寸解码、快门闪退三根因都要装新包验证。
2. **iOS 端侧推理（自动追焦）**：三条路已排除（Strip Style 无效、
   tflite_flutter 升级无效、官方 `litert` 包在 pub.dev 404）→
   需要真机崩溃日志才能继续。见 TODO.md「六、iOS 端待办与决策」。
3. **Android 侧源头限尺寸**：没有 Podfile 这种机制，`ResolutionPreset.max`
   在 108MP 机型上仍可能给出巨图；Dart 侧已兜住内存，可给
   camera_android_camerax 再加一层。
4. **融合/选帧在 Android 上的限尺寸**：iOS 已做，Android 走同一条路径（已通用）。
5. **iOS 动态照片（Live Photo）**：当前在 iOS 上是关的（`startVideoRecording`
   与拍照会话互斥嫌疑），要恢复得先解掉那条线。
6. **物化"实况图"**（iOS Live Photo）需要自写原生 channel，排在 Mac 环境就绪后。

## 十、给接手者（尤其是 AI）的提醒

- **先读 TODO.md 的「六之三」**——最近三次 iOS 事故的完整根因分析都在那，
  避免把已经证明无效的路子再走一遍（尤其"升级 tflite_flutter 能修 iOS 崩溃"）。
- **别用肉眼判断画质**，用 `tools/filter_lab` 的锐度比；也别用肉眼判断崩溃位置，
  用「拍照诊断日志」。
- **改参数前问一句"这会让峰值内存涨多少"**——本项目 90% 的线上事故是内存问题，
  不是逻辑问题。
- **不确定就加测试**：本项目的测试都是"契约式"的（钉死一条产品承诺），
  出现事故后第一件事就是补一条测试把承诺钉住。
- **别把用户的实拍照片提交进仓库**：`.filter_lab/` 已 gitignore。



