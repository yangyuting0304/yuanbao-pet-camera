# 元宝拍拍 —— 待办事项清单

> 整理日期：2026-08-31
> 更新日期：2026-09-01（确认云上种子图已存在、路径已锁定，归档至 DEPLOY.md）
> 本文档汇总当前项目的未完成任务、待决决策与已知问题，按优先级（P0=阻塞上线 / P1=重要 / P2=优化）排列。

---

## 一、当前改造进度总览

| 改造项 | 状态 | 结果 |
|---|---|---|
| 中文字体子集化 | ✅ 已完成 | `NotoSansSC.ttf` 16.95 MB → 3.57 MB（-79%），原字体备份于 `build/font-backup/` |
| 种子图外置 COS | ✅ 已完成 | Web 部署包 102.8 MB → ~60 MB；照片不再进安装包 |
| 种子图上传 | ✅ 已上传 | `upload.js` 上传 212 张到 `seed/photos/`，成功 212 / 失败 0（见 P0-1） |
| 上传工具 | ✅ 已完成 | `tools/seed-upload/upload.js`（增量上传 + MD5 校验） |
| 定时上传任务 | ⏳ 待创建 | 见 P0-4（云上已有图，非阻塞） |
| SEED_BASE_URL 默认值 | ✅ 已锁定 | `...cos.ap-guangzhou.myqcloud.com/seed`，实测 200（见 P0-2） |
| 短片页跨平台（dart:html） | ✅ 已修复 | 条件导入 `MediaPlatform` 抽象，analyze 零 error，见 P1-1 |
| AI 写真图生图链路 | ✅ 已升级 | 服务端 + 前端统一 wan2.7-image-pro multimodal，见 P1-2 |
| COS 静态站上传脚本 | ✅ 已改增量 | `deploy/cos_upload.py` 支持 ETag 跳过 / dry-run / prune，见 P2-2 |

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

### P2-2 上传脚本改增量/孤儿清理 【✅ 已改 2026-08-31】

- `deploy/cos_upload.py` 已改造：
  - 增量上传：`head_object` 拿 ETag（单对象 PUT = MD5）比对，一致即跳过
  - `--dry-run` 预览待上传/待删除
  - `--prune` 清理远端孤儿（自动保护 `seed/`、`temp/`、`firered/` 前缀）
- 用法：
  ```powershell
  python deploy/cos_upload.py --dry-run   # 预览
  python deploy/cos_upload.py             # 增量上传
  python deploy/cos_upload.py --prune     # 增量 + 清理孤儿
  ```

### P2-3 双图标库合并

- `lucide_flutter` 与 MingCute SVG 并存（`pubspec.yaml` 注释自述"旧页面暂时还在使用"），建议统一到 MingCute 后移除 `lucide_flutter`。
- **状态（2026-08-31）**：跳过 —— 迁移涉及 `IconData → MingCute String 名` 的数据模型与多个页面渲染改动，属于 UI 调整，先讨论再动。使用点：`ai_portrait_service.dart`（6 个风格图标）、`retouch_data.dart`（3 个贴纸图标）。

---

## 五、操作备忘

### 字体子集化重跑（新增 UI 文案后）

```powershell
node tools/font-subset/subset.js                 # 自动纳入新字符
node tools/font-subset/subset.js --preset=source # 只要源码字符（最小体积）
# 回退原字体：
copy build\font-backup\NotoSansSC.ttf assets\fonts\NotoSansSC.ttf
```

### 种子图上传

```powershell
node tools/seed-upload/upload.js --dry-run   # 预览待上传
node tools/seed-upload/upload.js             # 正式上传（增量）
```

### 静态站部署（增量）

```powershell
python deploy/cos_upload.py --dry-run   # 预览
python deploy/cos_upload.py --prune     # 增量上传 + 清理孤儿
```

### 关键环境变量汇总

| 变量 | 用途 | 状态 |
|---|---|---|
| `COS_SECRET_ID/KEY` | 种子图上传（seed-upload）+ 静态站部署 | ⏳ 待填 |
| `TENCENT_COS_SECRET_ID/KEY` | AI 代理旧版路径 `/api/upload` 云持久化 | ⏳ 待填（写真新链路已不依赖） |
| `SEED_BASE_URL` | App 种子图远程地址 | ✅ `...cos.ap-guangzhou.myqcloud.com/seed`，已上传可访问（P0-2） |
| `DASHSCOPE_API_KEY` | 百炼写真 | ✅ 已填（ai_portrait/.env） |
| `MAAS_BASE_URL` | 百炼 workspace 专属 base | ✅ 已填（ai_portrait/.env） |
| `MODELSCOPE_API_KEY` | FireRed 美颜 | ⏳ 待填（firered_edit 无 .env） |
| `AI_PROXY_URL` | 写真代理 | ⏳ 待填（部署代理后构建注入） |
| `FIERED_PROXY_URL` | FireRed 代理 | ⏳ 待填（部署代理后构建注入） |

---

## 六、待你决策的事项

1. **P0-4 定时任务的频率 / 范围 / 凭据来源**（上一轮提问尚未回答）。
2. **P2-1 缩略图方案**：本地生成 vs 数据万象 CI。
3. ~~**SEED_BASE_URL 实测结果**~~（✅ 已锁定 COS 前缀，见 P0-2）。
4. ~~**是否把本清单 + 部署流程补进 `DEPLOY.md`**~~（✅ 已归档，含种子图外置 + 两套脚本分工 + 费用说明）。
5. **P2-3 图标库合并是否执行**（涉及 UI 展示变化，先讨论）。
