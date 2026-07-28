# 元宝爱拍照 — v1 构建与运行指南（Android 主演示端）

> 当前状态：本仓库已写好 **第一片可运行骨架**（路由 + 设计 Token + 8 页占位 + Riverpod/Lucide 接入）。
> 平台策略：**Android 为 v1 主演示端，iOS 暂搁**（详见 `docs/decisions/ADR-001-platform-target.md`）。

## 一、安装工具链（一次性）
1. 安装 **Flutter 3.44 stable**（含 Dart 3.12.x）：https://flutter.dev/sdk-archive
2. 安装 **Android Studio**（一站式带 JDK / Android SDK / 模拟器）：https://developer.android.com/studio
3. 打开 Android Studio → SDK Manager → 装 **Android SDK Platform 35** + **Build-Tools** + 一台 **Pixel 模拟器**（或直接用安卓真机 USB 调试）。
4. 终端跑 `flutter doctor`，按提示补全（主要就是 Android 许可 `flutter doctor --android-licenses`）。

## 二、生成平台脚手架（关键一步）
Flutter 的 `android/`、`ios/` 等平台目录需由工具链生成，无法手写完整。请在仓库**根目录**执行：

```bash
cd F:\元宝爱拍照
# 1) 先让工具链生成一套干净脚手架（临时目录）
flutter create --org com.yuanbao _scaffold

# 2) 把生成的平台目录拷进我们的项目（android 必选；ios 暂不需要可跳过）
xcopy /E /Y _scaffold\android pet_camera\android\
xcopy /E /Y _scaffold\ios    pet_camera\ios\

# 3) 清理临时目录
rmdir /S /Q _scaffold
```

> 之后所有业务逻辑都写在 `pet_camera/lib/`，平台目录不要手改。

## 三、拉依赖 + 跑起来
```bash
cd F:\元宝爱拍照\pet_camera
flutter pub get
flutter run          # 选安卓模拟器或已连接的真机
```

## 四、常见问题
- **`pub get` 报某个包版本不存在**（如 `lucide_icons` / `flutter_riverpod`）：
  直接 `flutter pub add lucide_icons flutter_riverpod` 让工具链取最新稳定版，再 `flutter pub get`。
- **`pawPrint` 等图标名编译报错**：说明当前 `lucide_icons` 版本未导出该图标，
  到 `lib/app/pages.dart` 把对应 `LucideIcons.xxx` 换成存在的名字即可（禁 emoji）。
- **相机功能在模拟器上没画面**：属正常，相机类请用**安卓真机** USB 调试验证。

## 五、后续切片（按顺序叠加，不动本骨架）
1. Drift 本地库（pets/photos/albums/ai_tasks/video_projects）+ 金元宝种子数据导入
2. camera 插件接入拍照页
3. 云端 AI 写真（通义万相 + CogView）
4. AI 剪辑短片（即梦/可灵 + ffmpeg_kit 本地合成）
5. 智能 P 图（Remove.bg + 端侧滤镜）
