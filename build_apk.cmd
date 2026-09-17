@echo off
REM 元宝拍拍 —— Android release APK 一键构建。
REM
REM 背景：本项目工作区路径含中文（F:\元宝爱拍照），Windows 上 Gradle 传给
REM Dart AOT 快照工具的路径会编码错乱，报 "Unable to read file ... app.dill"。
REM 且 F 盘是 exFAT 文件系统，无法创建 junction 联接绕行。
REM 解法：把源码镜像到纯 ASCII 路径 C:\yuanbao_build 构建，产物回拷到本项目。
REM 日常开发仍在 F 盘；本脚本只负责「同步 → 构建 → 回拷」。
setlocal
set DEST=C:\yuanbao_build
set SRC=%~dp0

robocopy "%SRC%" "%DEST%" /MIR /XD build .dart_tool _scaffold .gradle /XF *.log /NFL /NDL /NJH /NJS >nul
if errorlevel 8 ( echo [失败] 源码同步到 %DEST% 出错 & exit /b 1 )

pushd %DEST%
call flutter build apk --release
if errorlevel 1 ( popd & echo [失败] APK 构建失败，见上方日志 & exit /b 1 )
popd

robocopy "%DEST%\build\app\outputs\flutter-apk" "%SRC%build\app\outputs\flutter-apk" /E /NFL /NDL /NJH /NJS >nul
echo.
echo 完成：build\app\outputs\flutter-apk\app-release.apk
endlocal
