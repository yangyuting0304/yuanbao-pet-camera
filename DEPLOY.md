# 元宝拍拍 · 网页端上线部署文档

目标：把 Flutter Web 版「元宝拍拍」部署上线，iPhone（Safari）打开 HTTPS 链接即可用相机拍照、看相册、跑 AI 美颜。
架构：**腾讯云 COS 托管静态站 + 阿里云 ECS 跑 AI 美颜代理（千问免费图生图）**，两套云资源都用上，不额外花钱。

---

## 0. 前置：重新构建（已含瘦身 + 种子图外置 + 持久化 + 代理开关）

```bash
cd pet_camera
# 设置国内镜像（每次新终端都要）
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# 若改过 assets/pubspec 必须 clean
flutter clean
flutter build web --release

# 如需启用 AI 美颜，构建时追加（URL 见第四节）：
flutter build web --release --dart-define=AI_PROXY_URL=https://你的代理域名/api/beautify
```
产物在 `build/web/`（约 60MB；种子图已外置、字体已子集化，详见下节）。

---

## 0.5 种子图外置 + 字体子集化（2026-09-01 已落地）

### 背景
- 种子图 `assets/seed/photos/` 原 214 个文件 / 57.2MB，全量打进安装包/部署包导致虚胖。
- 现改为**外置到 COS**，App 按 `SEED_BASE_URL + 文件名` 远程加载，不再随包分发。

### 体积优化（已完成）
| 项 | 前 | 后 |
|----|----|----|
| 中文字体 `NotoSansSC.ttf` | 16.95 MB | 3.57 MB（子集化，`tools/font-subset/`） |
| Web 部署包 `build/web` | 102.8 MB | ~60 MB（seed 图不再打包） |
| 打包种子图 | 57.2 MB | 0.8 MB（仅保留示例视频） |

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

### 两套脚本分工
| 脚本 | 用途 | 同步目标 | 现在还需改吗 |
|------|------|---------|-------------|
| `tools/build_web_preview.sh` | **本地预览**（同步到仓库上两级的本地目录 + http.server） | 本地文件夹 | 否；`SYNC_ITEMS` 每项都是 Web 必需产物 |
| `deploy/cos_upload.py` | **部署上线**（上传 `build/web` 到 COS `yuanbao-pet-camera/` 前缀） | 腾讯云 COS | 否；增量上传 + `--prune` 保护 `seed/` 前缀 |

> `build_web_preview.sh` 的 `SYNC_ITEMS` 含 `assets`（字体/图标/AssetManifest）等 Web 必需产物，**种子图已自动不打包**，无需删项。
> `deploy/cos_upload.py` 的 `--prune` 会保护 `seed/` 前缀，不会误删种子图。

### 费用说明
- COS 存储约 0.099 元/GB/月；**上传（外网入）流量免费**，仅下载（外网下行）收费。
- 重新上传种子图几乎零成本（57MB 存储 ≈ 0.006 元/月 + PUT 请求 ≈ 0.01 元）。

### 后续可选优化（非必需）
- 已用干净前缀 `seed/photos/`，无需再处理 `assets/assets` 冗余段。
- 生成缩略图或开通数据万象 CI 省列表流量（见 `TODO.md` P2-1）。

---

## 1. 静态站部署到腾讯云 COS（今天就能出 iPhone 链接）

1. 装依赖：`pip install cos-python-sdk-v5`
2. 设置环境变量并上传：
   ```powershell
   $env:COS_SECRET_ID="xxx"; $env:COS_SECRET_KEY="xxx"
   $env:COS_BUCKET="pet-camera-xxxx"; $env:COS_REGION="ap-guangzhou"
   python deploy/cos_upload.py
   ```
3. 控制台开启「静态网站」：首页 = `index.html`、错误页 = `index.html`、强制 HTTPS。
4. 得到的地址形如 `https://<bucket>.cos-website.<region>.myqcloud.com/`，**自带 HTTPS、无需备案**，iPhone 直接开。

> 该域名若遇 HTTPS 异常（极少数新桶策略），可改用默认域名 `https://<bucket>.cos.<region>.myqcloud.com/index.html`，或绑定已备案自定义域名 + CDN。

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
4. 重新执行第 1 步上传 COS

未配置 `AI_PROXY_URL` 时，App 自动走「演示模式」回显原图，不影响相机/相册使用。

---

## 4. 环境变量速查

| 变量 | 用途 | 在哪设 |
|------|------|--------|
| `COS_SECRET_ID/KEY/BUCKET/REGION` | 上传静态站 + 代理临时图床 | 本地终端 / ECS `.env` |
| `DASHSCOPE_API_KEY` | 千问图生图密钥 | ECS `.env`（只放服务端） |
| `AI_PROXY_URL` | 前端调美颜代理的地址 | Flutter 构建期 `--dart-define` |

---

## 5. 已知限制 / 后续

- 种子图已外置到 COS，**App 加载相册需联网**；断网时显示占位/失败重试（`AppImage`）。
- 首次加载仍含 CanvasKit 引擎 + 子集化字体，体积较旧版大幅下降（~60MB 部署包，首屏按需下载）。
- AI 美颜依赖千问服务可用性 + 免费额度。
- 安卓原生包、短片生成、P 图等能力按计划后续迭代；安卓构建目前受 `dart:html`（短片）阻塞，见 `TODO.md` P1-1。
- 备案：COS 的 `*.myqcloud.com` 无需备案；ECS 若绑自定义域名需备案（用 API网关/FC 可免）。
