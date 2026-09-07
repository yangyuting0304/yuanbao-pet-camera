@echo off
REM ============================================================
REM 元宝拍拍 前端构建（读 frontend_env.json，无需手敲 --dart-define）
REM 线上访问带子路径 /yuanbao-pet-camera/，故加 --base-href
REM 产物输出到 build/web，可上传部署
REM ============================================================
cd /d "%~dp0"
echo [build_web] 使用 frontend_env.json 构建前端 (base-href=/yuanbao-pet-camera/)...
REM --no-web-resources-cdn：CanvasKit 不走 www.gstatic.com（国内不可达），
REM   改用产物内自带的 canvaskit/ 目录；tools/build_web_preview.sh 同样处理。
flutter build web --release --no-web-resources-cdn --base-href=/yuanbao-pet-camera/ --dart-define-from-file=frontend_env.json
