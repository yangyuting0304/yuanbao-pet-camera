# 元宝爱拍照 — 环境搭建与跑通指南（下载 → 安装 → 跑通）

> 适用对象：本机从零配置（Windows）。目标：在 Android 真机/模拟器上跑起 `pet_camera` 项目。
> 平台策略：**Android 为 v1 主演示端，iOS 暂搁**（详见 `docs/decisions/ADR-001-platform-target.md`）。
> 配套文档：本项目的「构建切片」说明见 `README_build.md`。

---

## 0. 先看系统是否满足

| 项目 | 最低要求 | 说明 |
|------|----------|------|
| 系统 | Windows 10/11 64 位 | x64 |
| 内存 | 8 GB+ | Android Studio + 模拟器较吃内存 |
| 磁盘 | 预留 **8 GB+** 空闲 | Flutter ~1GB + Android Studio/SDK/镜像 ~4GB + 缓存 |
| 已装 Git | 2.x | 本项目已确认本机有 Git 2.53；没有则先装 https://git-scm.com/download/win |
| 处理器 | 支持虚拟化的 Intel/AMD 64 位 | 开模拟器需要 |

---

## 1. 下载 Flutter SDK 3.44（稳定版）

> **推荐：直接用下方 Google 存储直链下载**（archive 页面的「证明包」按钮偶尔 NoSuchKey 报错，直链更可靠）。

| 版本 | Dart | 发布日期 | **直链下载（点即下）** |
|------|------|----------|----------------------|
| **3.44.7** ✅ 最新 | 3.12.2 | 2026/7/20 | [flutter_windows_3.44.7-stable.zip](https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.7-stable.zip) |
| 3.44.6 备选 | 3.12.2 | 2026/7/9 | [flutter_windows_3.44.6-stable.zip](https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.6-stable.zip) |
| 3.44.5 备选 | 3.12.2 | 2026/7/6 | [flutter_windows_3.44.5-stable.zip](https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.5-stable.zip) |

- 架构：**x64 X64**（普通 Windows 64 位电脑用）
- 中文镜像（官网慢时）：https://flutter.cn/docs/get-started/install/windows
- 手动安装说明（备用）：https://docs.flutter.dev/install/manual
- archive 页面（查看全部版本）：https://docs.flutter.dev/install/archive?tab=windows

## 2. 下载 Android Studio（一站式最省心）

1. 官方下载（自动识别 Windows）：https://developers.android.com/sdk
2. 点 **Windows (64-bit)** 的 `android-studio-quail1-patch2-windows.exe`（推荐 .exe 安装器，约 1.5GB）
   - 国内镜像（官网慢时）：https://developer.android.google.cn/studio
3. 双击 .exe 安装，**一路默认下一步**即可。安装器会顺手带上 **JDK 17 + Android SDK + 模拟器向导**，不用你单独配。

> 为什么推 Android Studio 而非纯 VS Code：你是产品/运营背景、非重度开发者，Studio 把 JDK、SDK、模拟器创建向导全打包了，装完 `flutter doctor` 基本一遍过；VS Code 更轻但要自己配 SDK 路径，容易卡环境。先求稳跑通。

---

## 3. 安装与解压（路径有讲究）

### 3.1 解压 Flutter
- 解压到 **无中文、无空格** 的路径，推荐：
  `C:\Users\yuting.yang1\dev\flutter`
- 解压后确认 `...\flutter\bin\flutter.bat` 存在（被杀软隔离时，把该目录加白名单后重新解压）。

### 3.2 安装 Android Studio
- 双击 .exe，默认下一步。
- **首次启动**会额外联网下载 SDK 组件（约 1~2GB，耐心等）。
- 启动后按向导：
  1. `SDK Manager` → 装 **Android SDK Platform 35** + **Build-Tools 35** + **Android SDK Command-line Tools**
  2. `Device Manager` → 新建一台 **Pixel 模拟器（API 35）**；或直接用安卓真机 USB 调试（相机类**强烈建议真机**）

---

## 4. 配置 PATH 环境变量

把 Flutter 的 bin 加进系统 PATH（PowerShell 或图形界面都行）：

**图形界面**：
`Win + Pause`（无 Pause 用 `Win + Fn + B`）→ 系统 → 关于 → 高级系统设置 → 高级 → 环境变量 → 用户变量 `Path` → 编辑 → 新建 → 填 `C:\Users\yuting.yang1\dev\flutter\bin` → 确定。

**或 PowerShell（管理员）**：
```powershell
[Environment]::SetEnvironmentVariable(
  "Path",
  $env:Path + ";C:\Users\yuting.yang1\dev\flutter\bin",
  "User"
)
```
> 改完**重开一个终端**让 PATH 生效。

---

## 5. 验证环境：flutter doctor

打开新的终端，依次跑：
```bash
flutter --version          # 应显示 Flutter 3.44.x / Dart 3.12.x
flutter doctor             # 看还缺什么
flutter doctor --android-licenses   # 一路 y 接受 Android 许可
```
`flutter doctor` 理想状态：
- [✓] Flutter
- [✓] Android toolchain
- [✓] Android Studio
- [!] 模拟器/真机：连上真机或建好模拟器后变绿

若报 "Android license status unknown" → 跑上面那条 `--android-licenses` 即可。

---

## 6. 准备设备

| 方式 | 操作 | 备注 |
|------|------|------|
| **安卓真机（推荐）** | 手机开「开发者选项 → USB 调试」，USB 连电脑，弹窗选「允许」 | 相机类必须用真机，模拟器拍不了真猫 |
| 模拟器 | Android Studio → Device Manager → 建 Pixel API 35 | 仅用于非相机页面调试 |

终端跑 `flutter devices` 能看到你的设备即 OK。

---

## 7. 跑起项目

完整构建与运行步骤（含平台脚手架生成）见 `README_build.md`。核心三步：

```bash
cd F:\元宝爱拍照

# A. 生成平台目录（一次性，工具链生成 android/ios，不手写）
flutter create --org com.yuanbao _scaffold
xcopy /E /Y _scaffold\android pet_camera\android\
rmdir /S /Q _scaffold

# B. 拉依赖并运行
cd pet_camera
flutter pub get
flutter run            # 选已连接的安卓真机/模拟器
```

起来后是一个有 **8 页路由 + 双主题 + 金元宝语境** 的可点 App 壳（设计 Token 严格按 Spec §8，无 emoji 图标、无紫粉渐变、无硬编码色）。

---

## 8. 常见问题速查

| 现象 | 处理 |
|------|------|
| `pub get` 报某包版本不存在（`lucide_icons`/`flutter_riverpod`） | `flutter pub add lucide_icons flutter_riverpod` 取最新稳定版，再 `flutter pub get` |
| 图标名 `LucideIcons.xxx` 编译报错 | 当前版本未导出该图标，到 `lib/app/pages.dart` 换成存在的名字（禁 emoji） |
| 相机页在模拟器上没画面 | 正常，相机类请用安卓真机 USB 调试 |
| `flutter.bat` 解压后不在 bin 目录 | 杀软隔离，加白名单后重新解压 |
| `flutter doctor` 报 license unknown | `flutter doctor --android-licenses` 一路 y |
| 真机 `flutter devices` 看不到 | 重开 USB 调试、换数据线、装 Google USB Driver |

---

## 9. 后续开发切片（不动本骨架，按序叠加）

1. Drift 本地库（pets/photos/albums/ai_tasks/video_projects）+ 金元宝种子数据导入
2. camera 插件接入拍照页
3. 云端 AI 写真（通义万相 + CogView）
4. AI 剪辑短片（即梦/可灵 + ffmpeg 本地合成）
5. 智能 P 图（Remove.bg + 端侧滤镜）

> AI 能力还需单独申请云端 API Key（Phase 3 开发前会另给清单）。
