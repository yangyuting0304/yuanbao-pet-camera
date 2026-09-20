# dist/ —— 构建产物分发目录

本目录存放**发布的 APK**，供测试人员直接下载（微信不允许传 APK 文件，但可以传 GitHub 链接）。

---

## 规则（重要）

**本目录永远只保留最新的一个包。**

出新包时，必须在**同一次提交**里删掉上一个版本：

```bash
# 1) 放入新包（版本号与 pubspec.yaml 的 version 保持一致）
#    Windows:  copy ..\build\app\outputs\flutter-apk\app-release.apk dist\yuanbao-pet-camera-v1.0.1.apk
#    macOS:    cp build/app/outputs/flutter-apk/app-release.apk dist/yuanbao-pet-camera-v1.0.1.apk

# 2) 删除旧包
git rm dist/yuanbao-pet-camera-v1.0.0.apk

# 3) 一起提交
git add -A
git commit -m "chore(dist): 更新 APK 到 v1.0.1"
```

## 为什么必须这样

APK 约 **82MB**。如果每次构建都新增而不删除：

| 构建次数 | 仓库增长 |
|---|---|
| 1 次 | +82MB |
| 10 次 | +820MB |
| 20 次 | +1.6GB |

而且 **git 会把每一版永久留在历史里**——之后删掉文件也不会让仓库变小。

本仓库历史上就曾因为把 `release/` 目录（404MB）入库而膨胀到 **1.76GB**，后来专门做了一次瘦身才降下来。

> 一句话：**只保留一个包**能避免继续变大；想让仓库真正变小，只能重写历史。

## 命名规范

```
yuanbao-pet-camera-v<版本号>.apk
```

版本号与 `pubspec.yaml` 里的 `version:` 对应（如 `1.0.0+1` 取 `v1.0.0`）。

## 推送注意（82MB 大文件）

直接 `git push` 会失败，报：

```
error: RPC failed; curl 55 Send failure: Connection was reset
send-pack: unexpected disconnect while reading sideband packet
```

原因是超过了 git 默认 1MB 的 HTTP 缓冲。加临时参数即可：

```bash
git -c http.postBuffer=524288000 push origin main
```

`-c` 只对这一次命令生效，**不会修改你的 git 配置文件**。

GitHub 还会给出 `GH001: Large files detected` 的警告，那只是建议值（>50MB），不影响上传（硬限制 100MB）。

## 长期方案

如果出包变得频繁，建议改用 **GitHub Releases** 附件分发：

- 不占仓库体积
- 有固定的下载页面与直链，可写更新说明
- 不需要为每次构建重写 git 历史

届时本目录可以只留一个指向最新 Release 的说明文件。
