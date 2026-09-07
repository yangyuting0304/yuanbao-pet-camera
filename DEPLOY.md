# 元宝拍拍 · 网页端上线部署文档

目标：把 Flutter Web 版「元宝拍拍」部署上线，iPhone（Safari）打开 HTTPS 链接即可用相机拍照、看相册、跑 AI 美颜。
架构：**阿里云 ECS 用 nginx 托管前端静态站 + 同机跑 AI 代理（通义万相 / 百炼图生图）**；腾讯云 COS 只存媒体资源（种子图、拍摄的照片与视频、相册清单），**不再托管前端**。

---

## 0. 前置：重新构建（已含瘦身 + 种子图外置 + 持久化 + 代理开关）

```bash
cd pet_camera
# 设置国内镜像（每次新终端都要）
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# 若改过 assets/pubspec 必须 clean
flutter clean
flutter build web --release --no-web-resources-cdn --base-href=/yuanbao-pet-camera/

# 如需启用 AI 美颜，构建时追加（URL 见第四节）：
flutter build web --release --no-web-resources-cdn --base-href=/yuanbao-pet-camera/ --dart-define=AI_PROXY_URL=https://你的代理域名/api/beautify
```
> `--no-web-resources-cdn` 必须保留：否则 CanvasKit 会去 `www.gstatic.com` 下载，国内取不到就会一直卡在「元宝拍拍加载中…」。

产物在 `build/web/`（约 46MB，含本地 `canvaskit/` 约 37MB；种子图已外置、字体已子集化，详见下节）。

---

## 0.5 种子图外置 + 字体子集化与延迟加载（2026-09-01 落地，2026-09-07 升级）

### 背景
- 种子图 `assets/seed/photos/` 原 214 个文件 / 57.2MB，全量打进安装包/部署包导致虚胖。
- 现改为**外置到 COS**，App 按 `SEED_BASE_URL + 文件名` 远程加载，不再随包分发。

### 体积优化（已完成）
| 项 | 前 | 后 |
|----|----|----|
| 中文字体 `NotoSansSC.ttf` | 16.95 MB | 3.57 MB（子集化，`tools/font-subset/`） |
| 中文字体（首屏阻塞） | 3.57 MB 首帧前必下 | 0（改为运行时加载）；字体本体再降到 2×1.16 MB |
| Web 部署包 `build/web` | 102.8 MB | ~60 MB（seed 图不再打包） |
| 打包种子图 | 57.2 MB | 0.8 MB（仅保留示例视频） |

### 中文字体不再阻塞首帧（2026-09-07）
- 现象：字体声明在 `pubspec.yaml` 的 `flutter.fonts` 时，Flutter Web 会**等字体下载完才渲染首帧**，
  3.5 MB 子集在弱网实测拖到 28 秒，一直停在「元宝拍拍加载中…」。
- 做法：
  1. `pubspec.yaml` 不再声明 `fonts`，字体只作普通 asset 打包；
  2. `lib/data/app_font.dart` 用 `FontLoader` 在启动时注册，最长只等 800 ms
     （`kBrandFontWait`），超时先渲染首屏、字体后台继续下载；
  3. 字体再压缩：GB2312 一级字库（3755 常用字）+ 源码字符，可变字重固化成
     400/700 两个静态文件（`NotoSansSC-400/700.ttf`，各 1.16 MB）。
- 母版：`tools/font-subset/source/NotoSansSC-variable.ttf`（3.57 MB，未 pin 的可变字体），
  重新生成字重必须基于它，不能拿已 pin 的字体二次加工。

### 远程地址配置（`lib/data/seed_config.dart`）
```dart
// baseUrl 指向 .../seed，photoUrl 拼 /photos/<fileName>。
static const String baseUrl = String.fromEnvironment(
  'SEED_BASE_URL',
  defaultValue: 'https://pet-camera-1322296918.cos.ap-guangzhou.myqcloud.com/seed',
);
static String photoUrl(String fileName) => '$baseUrl/photos/$fileName';
// 例：https://pet-camera-1322296918.cos.ap-guangzhou.myqcloud.com/seed/photos/feat_album.jpg
```
- **2026-09-01**：种子图已用 `tools/seed-upload/upload.js` 上传到干净前缀 `seed/photos/`（212 张，成功 212 / 失败 0，含 ETag 校验）。用户清空桶后重传。
- 云上结构 `seed/photos/「fileName」` 平铺，与本地 `assets/seed/photos/` 文件名一一对应，公开读（HTTP 200 已验证）。
- 覆盖 baseUrl：`flutter build web --dart-define=SEED_BASE_URL=https://...`

### 种子图上传
```powershell
$env:COS_SECRET_ID="..."; $env:COS_SECRET_KEY="..."
$env:COS_BUCKET="pet-camera-1322296918"; $env:COS_REGION="ap-guangzhou"
node tools/seed-upload/upload.js --dry-run   # 预览待上传（增量）
node tools/seed-upload/upload.js             # 正式上传
```

### 脚本分工
| 脚本 | 用途 | 目标 |
|------|------|------|
| `tools/build_web_preview.sh` | **本地预览**（同步到仓库上两级的本地目录 + http.server） | 本地文件夹 |
| `sync_build.py` | **打包待上传**（`build/web` → `build/yuanbao-pet-camera/` + `build/web-deploy.zip`） | 本地 `build/` |
| `tools/seed-upload/upload.js` | **种子图增量上传**（到 COS `seed/photos/`） | 腾讯云 COS |

> `build_web_preview.sh` 的 `SYNC_ITEMS` 含 `assets`（字体/图标/AssetManifest）等 Web 必需产物，**种子图已自动不打包**，无需删项。
> 前端静态资源已不再上传 COS（`deploy/cos_upload.py` 已于 2026-09-04 删除），上传 ECS 的方式见下节与 `ECS_DEPLOY.md`。

### 费用说明
- COS 存储约 0.099 元/GB/月；**上传（外网入）流量免费**，仅下载（外网下行）收费。
- 重新上传种子图几乎零成本（57MB 存储 ≈ 0.006 元/月 + PUT 请求 ≈ 0.01 元）。

### 后续可选优化（非必需）
- 已用干净前缀 `seed/photos/`，无需再处理 `assets/assets` 冗余段。
- 生成缩略图或开通数据万象 CI 省列表流量（见 `TODO.md` P2-1）。

---

## 1. 静态站部署到 ECS（nginx 托管）

前端静态资源部署在阿里云 ECS，由 nginx 直接托管。完整步骤（上传 / nginx 配置 / 免费证书 / 安全组）见 **`ECS_DEPLOY.md`**。

概要：
```bash
# 1) 构建（--base-href 与访问路径一致；--no-web-resources-cdn 避免 CanvasKit 走 Google CDN）
flutter build web --release --no-web-resources-cdn --base-href=/yuanbao-pet-camera/

# 2) 打包成与 URL 子路径同名的目录（可选，另产出 build/web-deploy.zip 供面板上传）
python sync_build.py

# 3) 上传：产物目录名 = URL 子路径名
scp -r build/yuanbao-pet-camera root@<你的ECS公网IP>:/www/wwwroot/yangyuting.cloud/
```

要点：
- 站点根 `/www/wwwroot/yangyuting.cloud/`（宝塔默认站点目录），应用落在 `/www/wwwroot/yangyuting.cloud/yuanbao-pet-camera/`，访问地址 `https://yangyuting.cloud/yuanbao-pet-camera/`。
  `--base-href` 必须与实际访问路径一致，否则资源 404。
- nginx 需配 `try_files $uri $uri/ /index.html;`，否则刷新或直接打开子页面会白屏。
- iOS Safari 调起相机必须 HTTPS，证书申请见 `ECS_DEPLOY.md` 第 4 步。
- 静态文件覆盖后无需重启 nginx。

---

## 2. 拍摄照片持久化（已内置）

`lib/data/captured_photos.dart` 用 Hive 在 Web 走 IndexedDB：iPhone 上拍的照片刷新 / 杀进程不丢。无需额外配置。

---

## 3. AI 美颜（可选，第二阶段）

用你已有的**阿里云 ECS + 千问免费图生图**（`wanx2.1-imageedit`，免费 500 张）。

1. 部署代理：见 `cloud_functions/ai_portrait/README.md`
   - 本地 `npm install` → 填 `.env`（千问 Key + 腾讯云 COS 凭据）→ `node index.js`
   - 上 ECS：`systemd` 托管 + nginx/API网关 出 HTTPS
2. 拿到代理 HTTPS 地址 `https://<域名>/api/beautify`
3. **重新构建**并注入：`flutter build web --release --dart-define=AI_PROXY_URL=https://<域名>/api/beautify`
4. 重新执行第 1 步部署到 ECS

未配置 `AI_PROXY_URL` 时，App 自动走「演示模式」回显原图，不影响相机/相册使用。

---

## 4. 环境变量速查

| 变量 | 用途 | 在哪设 |
|------|------|--------|
| `COS_SECRET_ID/KEY/BUCKET/REGION` | 种子图上传（seed-upload）+ 代理临时图床 | 本地终端 / ECS `.env` |
| `DASHSCOPE_API_KEY` | 千问图生图密钥 | ECS `.env`（只放服务端） |
| `AI_PROXY_URL` | 前端调美颜代理的地址 | Flutter 构建期 `--dart-define` |

---

## 5. 已知限制 / 后续

- 种子图已外置到 COS，**App 加载相册需联网**；断网时显示占位/失败重试（`AppImage`）。
- 首次加载仍含 CanvasKit 引擎 + 子集化字体，体积较旧版大幅下降（~60MB 部署包，首屏按需下载）。
- AI 美颜依赖千问服务可用性 + 免费额度。
- 安卓原生包、短片生成、P 图等能力按计划后续迭代；安卓构建目前受 `dart:html`（短片）阻塞，见 `TODO.md` P1-1。
- 备案：站点在 ECS 上，绑定自定义域名需已完成备案（本项目 `yangyuting.cloud` 已备案）；IP 直连无需备案，但相机功能依赖 HTTPS，仍要配证书。
