#!/usr/bin/env bash

# 开启严格模式，尽早暴露路径或命令问题。
set -euo pipefail

# 当前脚本位于 repo/tools，下两级就是项目根目录。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_DIR="$(cd "${REPO_DIR}/../.." && pwd)"
BUILD_DIR="${REPO_DIR}/build/web"
PREVIEW_DIR="${WORKSPACE_DIR}"

# 默认使用项目内的 Flutter 3.44.9；也允许通过环境变量覆盖。
FLUTTER_BIN="${FLUTTER_BIN:-${WORKSPACE_DIR}/.sdk/flutter/bin/flutter}"

# 构建完成后，只同步这些 Flutter Web 产物。
# 这样可以避免整目录覆盖，更不会做删除操作。
# 注意：index.html 已内联加载逻辑（含 canvasKitBaseUrl），不再引用 flutter_bootstrap.js，
# 因此这里不同步该文件 —— 改加载行为请直接改 web/index.html。
SYNC_ITEMS=(
  "assets"
  "canvaskit"
  "icons"
  "favicon.png"
  "flutter.js"
  "flutter_service_worker.js"
  "index.html"
  "main.dart.js"
  "manifest.json"
  "version.json"
)

# 输出统一日志，方便后面排查。
log() {
  printf '[build_web_preview] %s\n' "$1"
}

# Flutter 命令必须在项目源码目录执行，否则 pub get 和 build web 找不到工程根目录。
cd "${REPO_DIR}"

# 检查 Flutter 可执行文件是否存在。
if [[ ! -x "${FLUTTER_BIN}" ]]; then
  log "未找到 Flutter：${FLUTTER_BIN}"
  exit 1
fi

log "使用 Flutter：${FLUTTER_BIN}"
"${FLUTTER_BIN}" --version

log "开始获取依赖"
"${FLUTTER_BIN}" pub get

log "开始构建 Web"
# 预览环境优先使用本地 Web 资源，避免 CanvasKit 走外部 CDN 时卡在启动 loading。
"${FLUTTER_BIN}" build web --base-href / --no-web-resources-cdn

log "开始安全同步到预览目录：${PREVIEW_DIR}"

# 逐项同步，不使用任何删除参数。
for item in "${SYNC_ITEMS[@]}"; do
  src_path="${BUILD_DIR}/${item}"
  dst_path="${PREVIEW_DIR}/${item}"

  # 不存在的构建产物直接跳过，避免误报。
  if [[ ! -e "${src_path}" ]]; then
    log "跳过不存在的产物：${src_path}"
    continue
  fi

  # 目录使用普通 rsync，同步新增和变更文件，但不删除目标已有内容。
  if [[ -d "${src_path}" ]]; then
    mkdir -p "${dst_path}"
    rsync -a "${src_path}/" "${dst_path}/"
    log "已同步目录：${item}"
    continue
  fi

  # 文件直接覆盖到目标位置，只更新这一个文件。
  cp -f "${src_path}" "${dst_path}"
  log "已同步文件：${item}"
done

# 本地预览使用 http.server 提供静态文件时，Service Worker 很容易把旧资源缓存住，
# 导致页面一直停在 loading。这里在同步完成后改写预览包的 index.html，
# 先注销旧的 Service Worker，再走普通加载流程（不再传 serviceWorkerSettings）。
# index.html 里 _flutter.loader.load({...}) 是唯一一处调用，非贪婪匹配到它的结尾 });
PREVIEW_INDEX_FILE="${PREVIEW_DIR}/index.html"
if [[ -f "${PREVIEW_INDEX_FILE}" ]]; then
  perl -0pi -e 's/_flutter\.loader\.load\(\{.*?\}\);/if ("serviceWorker" in navigator) {\n  navigator.serviceWorker.getRegistrations().then((registrations) => {\n    Promise.all(registrations.map((registration) => registration.unregister())).finally(() => {\n      _flutter.loader.load({ config: { canvasKitBaseUrl: "canvaskit" } });\n    });\n  });\n} else {\n  _flutter.loader.load({ config: { canvasKitBaseUrl: "canvaskit" } });\n}/s' "${PREVIEW_INDEX_FILE}"

  # 自检：确认替换真的生效（正则依赖 index.html 里 load 调用的写法，构建器改版会失配）。
  if grep -q 'registration.unregister' "${PREVIEW_INDEX_FILE}"; then
    log "已关闭预览环境 Service Worker"
  else
    log "警告：未能改写 index.html 的加载逻辑，Service Worker 仍会注册（预览可能读旧缓存）"
  fi
fi

log "预览同步完成"
