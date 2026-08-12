# 元宝拍拍 · 网页端上线部署文档

目标：把 Flutter Web 版「元宝拍拍」部署上线，iPhone（Safari）打开 HTTPS 链接即可用相机拍照、看相册、跑 AI 美颜。
架构：**腾讯云 COS 托管静态站 + 阿里云 ECS 跑 AI 美颜代理（千问免费图生图）**，两套云资源都用上，不额外花钱。

---

## 0. 前置：重新构建（已含瘦身 + 持久化 + 代理开关）

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
产物在 `build/web/`（约 117MB，已重压种子图 + canvaskit）。

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

- 首次加载约 40–80MB（canvaskit 占大头），后续访问有缓存。
- AI 美颜依赖千问服务可用性 + 免费额度。
- 安卓原生包、短片生成、P 图等能力按计划后续迭代。
- 备案：COS 的 `*.myqcloud.com` 无需备案；ECS 若绑自定义域名需备案（用 API网关/FC 可免）。
