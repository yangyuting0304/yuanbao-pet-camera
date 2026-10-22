# 元宝拍拍 —— 待办事项清单

> 整理日期：2026-08-31
> 更新日期：2026-09-01（确认云上种子图已存在、路径已锁定，归档至 DEPLOY.md）
> 更新：2026-09-04（前端静态站改由 ECS + nginx 托管，删除 `deploy/cos_upload.py`，COS 只保留媒体资源）
> 本文档汇总当前项目的未完成任务、待决决策与已知问题，按优先级（P0=阻塞上线 / P1=重要 / P2=优化）排列。

---

## 2026-10-22 当前增量

- [x] 用户确认的真实金元宝摄影师图标（三端）；保留画面右眼棕色痕。
- [x] 主体锚点裁切、动作候选、手动精彩标记、局部慢放与真实视频导出。
- [ ] 自动猫眨眼识别：需猫眼专用模型、授权数据、眨眼标注视频与误报验证；当前不冒充已实现。
- [ ] 移动主体自动追踪与光流补帧：未开启，不为此恢复iOS推理或购买云算力。
- [ ] 新iOS视频时间线和抽帧继续待Codemagic/iPhone实测，Android编码需真机复验。

## 2026-10-21 晚间任务状态（当前优先）

- [x] 正式元宝猫图标，接入 Android/iOS/Web，保留无透明通道高分辨率原图。
- [x] 首页四项功能完成入口与本地闭环；本地照片导入、结果保存/分享、明确失败提示。
- [x] 一键成片改为本地照片模板/单视频裁剪、排序、2～4秒照片时长、字幕、配乐、真实视频导出。
- [x] 删除 AI 视频 UI/任务/轮询/模型适配器；后端旧生成接口改410（仅源码，未部署）。
- [x] 成长档案与记录可新建、编辑、删除、持久化、JSON 导出，不再自动填充虚构健康记录。
- [x] Web 照片、短片刷新恢复；短片列表只持有引用，按需读视频字节。
- [ ] **iOS 必须云构建 + 真机验收**：AVFoundation 导出、相册权限/分享、48MP/连拍闪退回归；Windows 不得标为已测。
- [ ] **Android 真机验收**：Media3 导出、后台切换与相册授权；APK 编译通过不等于硬件编码器已实测。
- [ ] AI 写真/云端图像编辑的现有服务与凭据需可用；本次不发起付费生成，不新增付费服务。
- [ ] 若要线上彻底关闭旧 AI 视频 API，需要后续人工批准部署本次后端源码；本次没有部署生产。
- [ ] 自选音乐需用户自行准备本地音频；不接入收费曲库。

下面的旧事项为历史记录；如与本节冲突，以本节与本次交接为准。

## 一、当前改造进度总览

| 改造项 | 状态 | 结果 |
|---|---|---|
| 中文字体子集化 | ✅ 已完成 | `NotoSansSC.ttf` 16.95 MB → 2×1.16 MB（-86%），母版存于 `tools/font-subset/source/` |
| 中文字体阻塞首帧 | ✅ 已修复 | 2026-09-07：不再声明 `flutter.fonts`，改为 `FontLoader` 运行时注册 + 800ms 限时等待（首屏曾因此卡 28 秒） |
| 种子图外置 COS | ✅ 已完成 | Web 部署包 102.8 MB → ~60 MB；照片不再进安装包 |
| 种子图上传 | ✅ 已上传 | `upload.js` 上传 212 张到 `seed/photos/`，成功 212 / 失败 0（见 P0-1） |
| 上传工具 | ✅ 已完成 | `tools/seed-upload/upload.js`（增量上传 + MD5 校验） |
| 定时上传任务 | ⏳ 待创建 | 见 P0-4（云上已有图，非阻塞） |
| SEED_BASE_URL 默认值 | ✅ 已锁定 | `...cos.ap-guangzhou.myqcloud.com/seed`，实测 200（见 P0-2） |
| 短片页跨平台（dart:html） | ✅ 已修复 | 条件导入 `MediaPlatform` 抽象，analyze 零 error，见 P1-1 |
| AI 写真图生图链路 | ✅ 已升级 | 服务端 + 前端统一 wan2.7-image-pro multimodal，见 P1-2 |
| 前端部署方式 | ✅ 已切换 | 2026-09-04：静态站改由 ECS + nginx 托管，`deploy/cos_upload.py` 已删除；COS 只留 `seed/`、`temp/`、`firered/` |

---

## 二、P0 —— 阻塞项（需用户提供信息或操作）

### P0-1 补 COS 凭据并上传种子图 【✅ 已完成 2026-09-01】

- **已用 `tools/seed-upload/upload.js` 上传全部种子图到干净前缀 `seed/photos/`**：
  - 上传 **212 张**（209 jpg + 3 png），成功 212 / 失败 0（含 ETag 一致性校验）。
  - 上传前提条件：用户先清空存储桶，再执行上传。
- **上传位置**：桶的 `seed/photos/` 前缀（干净路径，去掉了旧 `assets/assets` 冗余段）。
- `upload.js` 保留备用（后续新增照片增量上传用）。
- 遗留：`TENCENT_COS_SECRET_ID/KEY` 仍未填，仅影响旧版 `/api/upload` 云持久化（写真新链路已不依赖，见 P1-2）。

### P0-2 验证 SEED_BASE_URL 访问路径 【✅ 已锁定 2026-09-01】

- **已上传到干净前缀并更新 `SEED_BASE_URL`**（用户提供新地址）：
  ```dart
  baseUrl = 'https://pet-camera-1322296918.cos.ap-guangzhou.myqcloud.com/seed'
  photoUrl(fileName) => '$baseUrl/photos/$fileName';
  // 例：.../seed/photos/feat_album.jpg（HTTP 200 已验证）
  ```
- 云上结构：`seed/photos/「fileName」` 平铺，与本地 `assets/seed/photos/` 文件名一一对应。
- 覆盖 baseUrl：`flutter build web --dart-define=SEED_BASE_URL=https://...`

### P0-3 补 AI 代理密钥（AI 写真 / 美颜才真出图）

- **状态（2026-08-31）**：`DASHSCOPE_API_KEY` 已填 ✅；`TENCENT_COS_SECRET_ID/KEY` 与 `MODELSCOPE_API_KEY` 仍为空 ⏳。
- **重要变化**：服务端已升级为 wan2.7-image-pro + base64 内联图（见 P1-2），**写真链路不再依赖 COS 凭据**，只需 `DASHSCOPE_API_KEY` + `MAAS_BASE_URL`（均已配置）即可真出图。
- 剩余待填：
  - `TENCENT_COS_SECRET_ID/KEY`（旧版 wanx2.1-imageedit 兼容路径 / `/api/upload` 云持久化）
  - `MODELSCOPE_API_KEY`（`cloud_functions/firered_edit/.env`，目前该目录还没有 `.env` 文件，需复制 `.env.example` 填写）

### P0-4 创建「种子图定时上传」任务

- **状态（2026-08-31）**：依赖 P0-1 凭据，且需用户确认频率/范围/凭据来源，自动化跳过。
- **问题**：`upload.js` 是增量上传（MD5 比对跳过），非常适合定时跑；新增照片后自动同步，无需手动。
- **待确认**：执行频率（建议每天一次）、是否仅上传（不建议捆绑构建部署，构建耗时且需锁文件）、凭据来源（已填 env 或读配置文件）。
- **参考命令**（每天 02:00）：
  ```powershell
  schtasks /Create /TN "YuanBaoSeedUpload" /TR "powershell -NoProfile -Command \"cd D:\code\yuanbao-pet-camera; node tools/seed-upload/upload.js\"" /SC DAILY /ST 02:00
  ```
  （凭据需预先写入环境变量或脚本内读取。）

---

## 三、P1 —— 重要（功能正确性 / 跨平台）

### P1-1 修复 Android 构建失败（`dart:html` 平台不兼容）【✅ 已修复 2026-08-31】

- **现象**：`flutter build apk` 失败，报错集中 `lib/app/short_video_page.dart`：
  ```
  Error: Dart library 'dart:html' is not available on this platform.
  Error: Undefined name 'Url' / 'Blob'.
  ```
- **修复**：新增 `lib/app/media_platform*.dart` 条件导入抽象：
  - `media_platform_web.dart`：Web 端 blob URL（dart:html，仅 Web 编译）
  - `media_platform_io.dart`：Android/iOS 字节落临时文件，`VideoPlayerController.file` / `DeviceFileSource`
  - `short_video_page.dart` 全部改调 `MediaPlatform`，`dart:html` 已从主文件移除
- **验证**：`flutter analyze` 零 error；`flutter test` 通过；debug APK 构建验证中。
- **附带修复**：
  - `lib/app/pages.dart` `_AlbumViewState.initState` 调 `ModalRoute.of`（依赖 InheritedWidget）→ 移到 `didChangeDependencies`，修复潜在崩溃
  - `pubspec.yaml` 补 `cached_network_image`（`lib/app/app_image.dart` 依赖但未声明，会阻塞所有构建）
  - `test/widget_test.dart` 陈旧 counter 测试改为冒烟测试（原引用已删除的 `MyApp`）

### P1-2 完善 AI 写真「照片→写真」直连路径 【✅ 已升级 2026-08-31】

- **服务端**（`cloud_functions/ai_portrait/index.js`）：
  - 升级为 **wan2.7-image-pro**（读 `.env` 的 `MODEL`/`MAAS_BASE_URL`），端点走 workspace
    `.../api/v1/services/aigc/multimodal-generation/generation`
  - 源图 **base64 内联**（`data:image/jpeg;base64,...`），写真链路不再依赖 COS 图床
  - 兼容旧版 wanx2.1-imageedit（未配 MAAS_BASE_URL 时走 COS 上传路径，成功后清理临时图）
- **前端**（`lib/data/ai_portrait_service.dart`）：
  - `_submitTask` 由 wanx2.1-t2i 文生图 → wan2.7-image-pro 图生图（multimodal + base64）
  - 新增 `--dart-define=MAAS_BASE_URL` 支持；`_pollTask` 同步改用 workspace 域名
- **生产构建**：
  ```powershell
  flutter build web --release --base-href=/yuanbao-pet-camera/ --dart-define=AI_PROXY_URL=https://<代理域名>/api/beautify
  ```

---

## 四、P2 —— 优化（可延后）

### P2-1 生成缩略图（省流量 + 内存）

- 现状：九宫格/瀑布流在加载原图（平均 267 KB），`memCacheWidth` 只省内存、不省网络流量。
- 方向：本地生成 400px 缩略图，或开通腾讯云数据万象（CI）用 `?imageMogr2/thumbnail/400x` 实时生成。
- **状态（2026-08-31）**：跳过 —— 需你决策方案（本地生成需加图片处理依赖；数据万象需控制台开通），待讨论后实施。

### P2-2 上传脚本改增量/孤儿清理 【✅ 已改 2026-08-31；🗑 已废弃 2026-09-04】

- 原 `deploy/cos_upload.py`（增量上传 `build/web` 到 COS 静态站）已删除 —— 前端改为部署到 ECS（nginx 托管）。
  COS 现在只存媒体：`seed/`（种子图）、`temp/`、`firered/`（代理临时图 / 拍摄的照片与视频、相册清单）。
- 替补打包脚本 `sync_build.py`：`build/web` → `build/yuanbao-pet-camera/`（目录名 = URL 子路径名）+ `build/web-deploy.zip`；上传方式见 `ECS_DEPLOY.md`。
- 种子图仍走 `tools/seed-upload/upload.js`（增量 + MD5 校验），不变。

### P2-3 双图标库合并

- `lucide_flutter` 与 MingCute SVG 并存（`pubspec.yaml` 注释自述"旧页面暂时还在使用"），建议统一到 MingCute 后移除 `lucide_flutter`。
- **状态（2026-08-31）**：跳过 —— 迁移涉及 `IconData → MingCute String 名` 的数据模型与多个页面渲染改动，属于 UI 调整，先讨论再动。使用点：`ai_portrait_service.dart`（6 个风格图标）、`retouch_data.dart`（3 个贴纸图标）。

---

## 五、操作备忘

### 字体子集化重跑（新增 UI 文案后）

字体现已拆成 400/700 两个静态子集，母版保存在 `tools/font-subset/source/NotoSansSC-variable.ttf`。
**必须从母版重新生成**，不要拿已生成的文件二次加工：

```powershell
cd tools/font-subset
node subset.js --src=source/NotoSansSC-variable.ttf --gb=level1 --pin=400 --out=assets/fonts/NotoSansSC-400.ttf
node subset.js --src=source/NotoSansSC-variable.ttf --gb=level1 --pin=700 --out=assets/fonts/NotoSansSC-700.ttf
node subset.js --inspect=assets/fonts/NotoSansSC-400.ttf,assets/fonts/NotoSansSC-700.ttf  # 校验字重 400/700
```

- `--gb=level1` 只保留 GB2312 一级字库（3755 常用字）+ 源码里出现过的所有字符；
  改回全集用 `--gb=full`，只留源码字符用 `--preset=source`。
- 字体不再写在 `pubspec.yaml` 的 `flutter.fonts` 里，由 `lib/data/app_font.dart`
  运行时注册（避免阻塞 Web 首帧），新增字重文件记得同步 `kBrandFontAssets`。

### 种子图上传

```powershell
node tools/seed-upload/upload.js --dry-run   # 预览待上传
node tools/seed-upload/upload.js             # 正式上传（增量）
```

### 前端部署到 ECS

```powershell
build_web.cmd          # 构建（含 --no-web-resources-cdn + --base-href=/yuanbao-pet-camera/）
python sync_build.py   # 可选：打包成 build/yuanbao-pet-camera/ 与 build/web-deploy.zip
scp -r build/yuanbao-pet-camera root@<ECS_IP>:/www/wwwroot/yangyuting.cloud/   # 上传，无需重启 nginx
```

> `--no-web-resources-cdn` 别漏：漏了 CanvasKit 会去 `www.gstatic.com` 下载，国内取不到会一直卡在加载页。

### 关键环境变量汇总

| 变量 | 用途 | 状态 |
|---|---|---|
| `COS_SECRET_ID/KEY` | 种子图上传（seed-upload）+ 代理临时图床 | ⏳ 待填 |
| `TENCENT_COS_SECRET_ID/KEY` | AI 代理旧版路径 `/api/upload` 云持久化 | ⏳ 待填（写真新链路已不依赖） |
| `SEED_BASE_URL` | App 种子图远程地址 | ✅ `...cos.ap-guangzhou.myqcloud.com/seed`，已上传可访问（P0-2） |
| `DASHSCOPE_API_KEY` | 百炼写真 | ✅ 已填（ai_portrait/.env） |
| `MAAS_BASE_URL` | 百炼 workspace 专属 base | ✅ 已填（ai_portrait/.env） |
| `MODELSCOPE_API_KEY` | FireRed 美颜 | ⏳ 待填（firered_edit 无 .env） |
| `AI_PROXY_URL` | 写真代理 | ⏳ 待填（部署代理后构建注入） |
| `FIERED_PROXY_URL` | FireRed 代理 | ⏳ 待填（部署代理后构建注入） |

---

## 六、iOS 端待办与决策（2026-10-15 整理）

> 本节只讲 iOS。Android 端的拍摄链路（含端侧宠物检测）已验证可用。

### 7.1 已修复：拍照闪退（三轮定位）

| 轮次 | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 点「宠物」标签瞬间闪退回桌面 | 切模式时先建新控制器再 dispose 旧的，Camerax/AVFoundation 单会话约束下必失败 | 先 dispose + 延迟（iOS 800ms / Android 250ms） |
| 2 | 进宠物模式后未拍照就闪退 | `tflite_flutter` 推理在 iOS 上触发 native 崩溃 | iOS 禁端侧实时检测与物种识别、禁动态短片 |
| 3 | 点快门闪退 | **`ResolutionPreset.max` 在 AVFoundation 上会把 `activeFormat` 换成像素最高的 format**（iPhone 上= 48MP），而本App 出片链路是纯 Dart 逐像素处理，单帧 RGBA≈192MB，三四张就被 jetsam 杀掉 | `CaptureQuality.effectivePreset` 在 iOS 把「超清」封顶 `veryHigh`（≈12MP）；连拍封顶 3 张 |

顺带修掉：`camera 0.12.1` + `camera_avfoundation 0.10.3+1`（0.9.x 用废弃的
`isHighResolutionCaptureEnabled` 处理 max）。

### 7.2 未修复：iOS 端侧推理（自动追焦）—— 需要真机日志

iOS 上宠物模式**没有自动追焦与主体分区**，只能点按对焦。原因与已排除的路线：

| 试过的路子 | 结果 |
|---|---|
| 改 Strip Style / 保留符号 | 无效 → 不是符号可见性问题 |
| 升级 `tflite_flutter` 0.11.0 → 0.12.1（最新版） | 无效 → 两版 `ios/tflite_flutter.podspec` 逐字节相同，仍固定依赖 `TensorFlowLiteSwift 2.12.0` |
| 换 Google 官方 `litert` 包 | 不存在 → pub.dev 上 `litert` 返回 404；社区替代（flutter_litert 20 star、tflite_plus 6 star）体量不足以替换生产依赖 |

**结论：没有真机崩溃日志之前这条路走不通**，不要再猜。

**恢复步骤（需要你配合）**：

1. 云构建一个带开关的验证包（开关只为复现用，发布包不带）：
   ```bash
   flutter build ipa --dart-define=IOS_TFLITE_ENABLED=true
   ```
   开关定义见 `lib/data/app_env.dart` 的 `AppEnv.iosTfliteEnabled`，
   生效点见 `lib/data/pet_detector_io.dart` 的 `isAvailable`。
2. 装到 iPhone 上，进宠物模式复现闪退。
3. 拿到崩溃日志（Xcode → Window → Devices and Simulators → 选设备 →
   View Device Logs，或用 `idevicesyslog`），把崩溃栈发我。
4. 按栈顶帧对症下药；跑通后把 `iosTfliteEnabled` 默认值改成 `true` 正式启用。

### 7.3 iOS 上的既有功能取舍（当前状态，均为"能拍/能存"优先）

| 功能 | iOS 现状 | Android |
|---|---|---|
| 端侧实时宠物检测（追焦、主体分区） | 关（7.2） | 开 |
| 端侧物种识别 | 已随「只拍猫」停用 | 同样停用 |
| 动态照片（Live Photo） | 关（拍照会话上录短片是闪退嫌疑） | 开 |
| 画质档位 | 「超清」封顶 12MP | 「超清」=max |

---

## 六之二、画质事故复盘：锐化过度（2026-10-20 已修）

**用户反馈**：App 拍出来的效果很差，锐化过度了，还不如原相机。

**不是相机的锅，是我们的滤镜把锐度翻了一倍。** 用离线实验台
（`tools/filter_lab/preview.dart`）把用户实拍图喂进滤镜管线，量了
**锐度比**＝滤镜后拉普拉斯方差 ÷ 原图拉普拉斯方差：

| 版本 | 全图锐度比 | 主体区 | 背景区 | 过冲像素 | 最大单像素改动 |
|------|-----------|--------|--------|---------|--------------|
| 修复前（clarity .10 + texture .22） | **1.99** | 1.99 | >1.0 | 12.6% | 97/255 |
| 修复后（clarity .04 + texture .08） | 1.12~1.24 | 1.12~1.26 | 0.88~0.97 | 7~10% | 45~49 |

**四个根因**：

1. **毛发质感在高频上放大差异**，而宠物照背景（瓷砖、地板、树叶）恰恰
   全是高频纹理——分不清是猫毛还是地面，于是满屏一起放大，
   观感就是"砂纸"。→ texture 0.22 → 0.08。
2. **主体分区形同虚设**：背景底值 0.30 等于背景照样吃三成增强，
   而这张图背景全是高频瓷砖。→ 底值 0.30 → 0.08（实测背景锐度比
   从 >1.0 变成 0.88~0.97）。
3. **没有过冲保护**：unsharp 在边缘两侧产生正负过冲（白边/黑边）。
   → 新增软限幅 `_deltaSoftLimit`（6/255，三段式、无 `exp`，
   因为这是逐像素热路径）。实测最大单像素改动 97 → 45~49。
4. **无检测框时毛发质感打偏**：iOS 端侧检测是关的，拿不到主体框，
   毛发质感分不清猫毛与地面。→ 无主体框时 texture 减半。

**顺带修掉一个隐蔽 bug**：限幅最初作用在"锐化 + 降噪"的合并增量上，
把降噪削掉了一半（噪点压不下去，被既有测试抓到）。现在锐化与降噪
**分开记账**：限幅只管锐化，主体分区也只加权锐化（背景同样需要降噪）。

**新增防线**：`test/pet_filter_sharpness_test.dart` 钉死三条承诺——
全图锐度比 ≤ 1.30、背景区 ≤ 1.05、主体区 ≥ 0.95（不许磨糊）、
极端清晰度下单像素改动 ≤ 24。**以后谁再把参数调回"过度锐化"，测试会直接拦下。**

**实验台怎么用**（调参时先在这里看，别等真机）：

```bash
dart run tools/filter_lab/preview.dart <实拍图.jpg> <输出目录> current subject soft flat
```

输出对照图 + 锐度比/过冲指标。输入图是用户素材，放在 `.filter_lab/`
（已 gitignore，不入库）。

## 六之三、iOS 闪退与卡顿（2026-10-20 已修，待真机验证）

**症状（iPhone 14 Pro Max）**：第一天还能拍，第二天直接闪退，拍照模式很卡。

### 根因 1：iOS 的输出尺寸完全失控（48MP）—— 上一轮的「封顶」其实没生效

上一轮我以为把 iOS 的「超清」封顶到 `veryHigh` 就能限制输出尺寸，**这是错的**。
读 camera_avfoundation 0.10.3+1 的 Swift 源码后确认：

- `setCaptureSessionPreset` 对 `.veryHigh` 只设 `sessionPreset = .hd1920x1080`，
  **不动 activeFormat**（只有 `.max` 才切 activeFormat）；
- `start()` 里无条件调用 `configureMaxPhotoDimensions()`，把
  `capturePhotoOutput.maxPhotoDimensions` 设成**当前 activeFormat 支持的最大值**；
- 而 `capturePhoto` 只在 `resolutionPreset == .max` 时才显式设
  `settings.maxPhotoDimensions`，其余情况用 AVCapturePhotoSettings 的默认值
  ——也就是 output 的上限。

**结果：无论选哪档，iPhone 14 Pro Max 拍出来都是 48MP。**

### 根因 2：链路里有 5 处全尺寸解码

`img.decodeImage`（纯 Dart）把 48MP 铺成 **192MB RGBA**，还要 3~8 秒：

| 消费点 | 用途 | 状态 |
|--------|------|------|
| 毛色分析 | 只需 160px 采样 | 已限尺寸（缩到 320 再解） |
| 滤镜 | 逐像素处理 | 已限尺寸（缩到 3000 再解） |
| 连拍选帧 | 判断清晰度 | 仍是全尺寸（下一批） |
| 多帧融合 | 对齐 + 合成 | 仍是全尺寸（下一批） |
| 成片比例合成 | 裁切 | 仍是全尺寸（下一批） |

后三处在 iOS 上因为输出已被压到 12MP（48MB/张）而可以接受；
**Android 上的 48MP/108MP 机型仍有风险**，是下一批要做的。

### 根因 2 的收尾：三处全尺寸解码已修（2026-10-20 续）

| 消费点 | 修法 |
|--------|------|
| 多帧融合 `fuseFramesWithPick` | 主 isolate 用原生解码器把每帧解到统一尺寸，`TransferableTypedData` **零拷贝**移交进 isolate；isolate 内不再碰全尺寸 JPEG |
| 成片比例合成 `_composePhotoToSelectedRatio` | `ui.instantiateImageCodec` 加上 `targetWidth`（原本无参数 = 全尺寸解码） |
| 连拍选帧 `burst_selector` | 选帧早已并入 `fuseFramesWithPick`；顶层入口无调用者，已在文件头标注现状（`scoreSharpness` 仍被融合调用） |

关键细节：

- **为什么用 `TransferableTypedData`**：compute 默认会把参数**复制**一份，
  3 帧 3000px 的 RGBA 就是 81MB 复制 —— 正好抵消掉限尺寸省下的内存。
- **两条融合通路必须同源**：预解码通路的灰度图计算（`_graySmallFromRgba`）
  与旧路径的 `_graySmall` 用同样的 copyResize average 插值，否则对齐结果
  会不同，同一批照片会因走哪条路产出不同成片。融合数学本体
  （`_fusePlanes`）完全共用，不存在第二份实现。
- **新增防线** `test/frame_fusion_predecoded_test.dart`：预解码通路出片尺寸
  正确、与旧路径**画质相当**（拉普拉斯方差 ≥ 旧路径 75%）、尺寸不匹配的
  帧被安全跳过。

### 根因 3：历史照片 200 张全量常驻

`loadAll()` 把最多 200 张成片的字节**全部读进内存**（1~3MB/张 → 200~600MB 常驻）。
第一天内存是空的所以能拍；第二天启动回填把基线抬起来，叠加拍摄时的内存
峰值 → iOS jetsam 直接杀进程。**这正是「第一天能拍、第二天闪退」的形状**：
不是某个瞬间爆掉，而是长期占用。

### 本轮修复

1. **`ios/Podfile` 补丁**：在 `post_install` 里改写 camera_avfoundation 的
   `configureMaxPhotoDimensions()`，把输出上限压到 **12MP**。
   做法是「从该机型**确实支持**的尺寸集合里挑 ≤12MP 的最大者」——
   直接赋一个可能不被支持的尺寸会抛 Objective-C 异常（Swift 侧不可捕获），
   等于把闪退换个地方发生。补丁找不到目标代码时只打印警告，不阻断构建。
2. **新增 `lib/data/image_decode.dart`**：用引擎原生解码器
   （`dart:ui` 的 `instantiateImageCodec` + targetWidth，iOS 走 ImageIO
   缩略解码路径）先缩再解，内存与耗时只跟目标尺寸相关。毛色分析与滤镜
   已接入；Web 端与异常路径自动退回纯 Dart 解码。
3. **历史回填 200 → 24 张**（`photo_storage_io._maxRestore`）：更早的照片
   仍在磁盘上，云端 works.json 照常展示。

### 新增防线

`test/image_decode_test.dart`：限尺寸解码的尺寸正确性、坏数据不崩、
滤镜的「已解码像素」通路输出尺寸与给定像素一致（证明它没有偷偷去解
全尺寸 JPEG）。

### 仍需你验证

云构建一个 iOS 包（`codemagic.yaml` 走 `flutter build ipa`，Podfile 补丁
在 `pod install` 时自动生效），装机后确认：

1. 拍一张，看**成片分辨率**（应约 4032×3024，而不是 8064×6048）；
2. 连拍 3~5 张，看是否还闪退；
3. 进宠物模式，看是否还卡。

若 Podfile 补丁没生效（构建日志里应有「已把 iOS 照片输出上限压到 12MP」
或对应的警告），把日志给我。

## 六之四、连拍报「上一张尚未返回」（2026-10-21 已修，待真机验证）

**现场报错**：`CameraException(Previous capture has not returned yet., takePicture was called before the previous capture returned.)`。

**根因**：`Future.timeout` 只让 Dart 调用方停止等待，不会取消相机插件中的原生拍摄。
原连拍和自动毛色分析分别在 `takePicture()` 外套了 8 秒 / 10 秒超时；超时后
业务层释放 `_photoInFlight`，但相机控制器仍保持 `isTakingPicture=true`，下一次
快门便被 `CameraController.takePicture()` 拒绝，造成拍照失败。

**修复**：两个拍照入口等待 `takePicture()` 真正完成后再释放互斥；30 秒 UI 看门狗
只在没有相机请求飞行时复位，不再靠超时释放拍摄锁。分析与静态检查通过；需要在
iPhone 真机上连续拍摄验证。Windows 无法本机生成 iOS 包，需通过 Codemagic 云构建。

## 六、待你决策的事项（iOS 相关见上一节）

1. **P0-4 定时任务的频率 / 范围 / 凭据来源**（上一轮提问尚未回答）。
2. **P2-1 缩略图方案**：本地生成 vs 数据万象 CI。
3. ~~**SEED_BASE_URL 实测结果**~~（✅ 已锁定 COS 前缀，见 P0-2）。
4. ~~**是否把本清单 + 部署流程补进 `DEPLOY.md`**~~（✅ 已归档，含种子图外置 + 两套脚本分工 + 费用说明）。
5. **P2-3 图标库合并是否执行**（涉及 UI 展示变化，先讨论）。
