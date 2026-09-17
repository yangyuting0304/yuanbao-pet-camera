# 元宝拍拍 (yuanbao-pet-camera)

宠物影像作品集 Demo：基于 Flutter Web 的跨平台应用，集成云端 AI（通义万相 DashScope）实现**写真 / 相册 / 短片 / P 图**四大能力。

## 技术栈
- Flutter 3.x（Web 渲染器，纯 Dart 无 wasm 依赖）
- 图标库：lucide_flutter
- 云端 AI 代理：阿里云 ECS（Express 代理）+ 通义万相 / 百炼图像编辑 API
- 媒体存储：腾讯云 COS（种子图、拍摄的照片与视频、相册清单）；前端静态资源不上传 COS

## 在线访问
https://yangyuting.cloud/yuanbao-pet-camera/

> - 必须走 **https**：iOS Safari 只在安全上下文下授予相机权限，用 http 打开会拍不了照。
> - 证书 SAN 只含 `yangyuting.cloud`，**不带 `www`**，别用 `www.` 前缀访问（会报证书错误）。
> - 证书有效期至 **2026-11-01**（TrustAsia），到期前注意续期。

## 本地运行
```bash
flutter pub get
flutter run -d chrome --web-port=8080
```

## 构建与部署
```bash
# 域名版构建（base-href 必须与访问路径一致）
# --no-web-resources-cdn：CanvasKit 用产物自带的 canvaskit/，不去 Google CDN 下载（国内取不到会卡加载页）
flutter build web --release --no-web-resources-cdn --base-href=/yuanbao-pet-camera/
```
- 也可直接跑 `build_web.cmd`（读 `frontend_env.json`，不用手敲 `--dart-define`）
- 静态产物上传到 ECS `/www/wwwroot/yangyuting.cloud/yuanbao-pet-camera/`，由 nginx 托管，步骤见 `ECS_DEPLOY.md`
- 打包：`python sync_build.py` 产出 `build/yuanbao-pet-camera/`（目录名 = URL 子路径名）与 `build/web-deploy.zip`
- 产物约 46 MB，其中 `canvaskit/` 约 37 MB，本地加载不走 CDN

## 目录结构
- `lib/`：Flutter 应用源码
- `assets/seed/photos/`：种子宠物照片（金元宝 / 小棉花 / 小汤圆 / 猫友圈）
- `cloud_functions/`：AI 写真代理服务（Express）
- `DEPLOY.md` / `ECS_DEPLOY.md`：部署与运维说明

## 备案
粤ICP备2026033457号
粤公网安备44030002016568号
