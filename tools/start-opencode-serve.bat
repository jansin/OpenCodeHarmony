@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM  OpenCode PC Server 启动脚本（供鸿蒙手机端局域网连接）
REM  用法：双击本文件，或在终端执行 tools\start-opencode-serve.bat
REM ============================================================

set "PORT=4096"
set "HOST=0.0.0.0"
set "OPENCODE_SERVER_PASSWORD=opencode"

REM 切到仓库根目录（本脚本在 tools\ 下）
cd /d "%~dp0.."

echo.
echo ========================================
echo   OpenCode PC Server 启动步骤
echo ========================================
echo.

REM ---------- 步骤 1：检查 opencode 命令 ----------
echo [1/5] 检查 opencode 是否已安装...
where opencode >nul 2>&1
if errorlevel 1 (
  echo.
  echo [错误] 未找到 opencode 命令。
  echo 请先安装 OpenCode CLI，并确保已加入 PATH，例如：
  echo   npm install -g opencode-ai
  echo   或按 https://opencode.ai 官方文档安装
  echo.
  pause
  exit /b 1
)
for /f "delims=" %%i in ('where opencode') do set "OPENCODE_BIN=%%i" & goto :found_bin
:found_bin
echo       已找到：%OPENCODE_BIN%
echo.

REM ---------- 步骤 2：工作目录与密码 ----------
echo [2/5] 工作目录：%CD%
echo       服务密码：%OPENCODE_SERVER_PASSWORD%
echo       （手机端「连接」页密码填同样值；可用环境变量覆盖）
echo.

REM ---------- 步骤 3：探测本机局域网 IP ----------
echo [3/5] 探测本机局域网 IP...
set "LAN_IP="
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  set "CAND=%%a"
  set "CAND=!CAND: =!"
  echo !CAND! | findstr /r "^192\.168\." >nul && if not defined LAN_IP set "LAN_IP=!CAND!"
  echo !CAND! | findstr /r "^10\." >nul && if not defined LAN_IP set "LAN_IP=!CAND!"
  echo !CAND! | findstr /r "^172\." >nul && if not defined LAN_IP set "LAN_IP=!CAND!"
)
if not defined LAN_IP (
  set "LAN_IP=你的电脑局域网IP"
  echo       未能自动识别，请手动查看 ipconfig 中的 IPv4 地址。
) else (
  echo       检测到：%LAN_IP%
)
echo.

REM ---------- 步骤 4：连接提示 ----------
echo [4/5] 手机端填写信息：
echo       地址：http://%LAN_IP%:%PORT%
echo       密码：%OPENCODE_SERVER_PASSWORD%
echo.
echo       注意：
echo       - 手机与电脑须在同一局域网
echo       - Windows 防火墙若拦截，请允许端口 %PORT%
echo       - 本机监听 %HOST%:%PORT%（对局域网开放）
echo.

REM ---------- 步骤 5：启动服务 ----------
echo [5/5] 正在启动：opencode serve --port %PORT% --hostname %HOST%
echo       保持本窗口不要关闭；按 Ctrl+C 可停止服务。
echo ========================================
echo.

opencode serve --port %PORT% --hostname %HOST%
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo [错误] opencode serve 退出，代码=%EXIT_CODE%
  echo 常见原因：端口 %PORT% 已被占用，或 opencode 配置/鉴权失败。
) else (
  echo 服务已结束。
)
echo.
pause
exit /b %EXIT_CODE%
