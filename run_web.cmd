@echo off
REM ============================================================
REM 元宝拍拍 前端一键启动（读 frontend_env.json，无需手敲 --dart-define）
REM 用法：双击本文件，或在终端执行 run_web.cmd
REM 改后端地址：编辑 frontend_env.json
REM ============================================================
cd /d "%~dp0"
echo [run_web] 使用 frontend_env.json 启动前端...
REM 使用 web-server 避免 Flutter 连接 Chrome DevTools 端口失败；
REM 启动后在浏览器访问 http://localhost:8080。
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=8080 --dart-define-from-file=frontend_env.json
