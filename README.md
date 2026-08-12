# 元宝拍拍 (yuanbao-pet-camera)

宠物影像作品集 Demo：基于 Flutter Web 的跨平台应用，集成云端 AI（通义万相 DashScope）实现**写真 / 相册 / 短片 / P 图**四大能力。

## 技术栈
- Flutter 3.x（Web 渲染器，纯 Dart 无 wasm 依赖）
- 图标库：lucide_flutter
- 云端 AI 代理：腾讯云 COS 存图 + 阿里云 ECS（Express 代理）+ 通义万相图像编辑 API

## 在线访问
http://yangyuting.cloud/yuanbao-pet-camera/

## 本地运行
```bash
flutter pub get
flutter run -d chrome --web-port=8080
```

## 构建与部署
```bash
# 域名版构建（base-href 必须与访问路径一致）
flutter build web --base-href=/yuanbao-pet-camera/ --release
```
- 静态产物上传到腾讯云 COS 桶 `pet-camera-1322296918` 的 `yuanbao-pet-camera/` 前缀
- 访问加速：宝塔反向代理到 COS + 腾讯云 CDN 主域名回源

## 目录结构
- `lib/`：Flutter 应用源码
- `assets/seed/photos/`：种子宠物照片（金元宝 / 小棉花 / 小汤圆 / 猫友圈）
- `cloud_functions/`：AI 写真代理服务（Express）
- `DEPLOY.md` / `ECS_DEPLOY.md`：部署与运维说明

## 备案
粤ICP备2026033457号-2
