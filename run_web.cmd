@echo off
REM ============================================================
REM 元宝拍拍 前端一键启动（读 frontend_env.json，无需手敲 --dart-define）
REM 用法：双击本文件，或在终端执行 run_web.cmd
REM 改后端地址：编辑 frontend_env.json
REM ============================================================
cd /d "%~dp0"
echo [run_web] 使用 frontend_env.json 启动前端...
flutter run -d chrome --web-port=8080 --dart-define-from-file=frontend_env.json
