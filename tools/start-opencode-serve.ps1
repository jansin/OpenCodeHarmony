# OpenCode PC Server 启动脚本（PowerShell）
# 用法：在仓库根目录或任意处执行
#   powershell -ExecutionPolicy Bypass -File tools\start-opencode-serve.ps1

$ErrorActionPreference = 'Stop'

$Port = 4096
$HostName = '0.0.0.0'
$Password = if ($env:OPENCODE_SERVER_PASSWORD) { $env:OPENCODE_SERVER_PASSWORD } else { 'opencode' }
$env:OPENCODE_SERVER_PASSWORD = $Password

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host ''
Write-Host '========================================'
Write-Host '  OpenCode PC Server 启动步骤'
Write-Host '========================================'
Write-Host ''

# 1. 检查 opencode
Write-Host '[1/5] 检查 opencode 是否已安装...'
$oc = Get-Command opencode -ErrorAction SilentlyContinue
if (-not $oc) {
  Write-Host ''
  Write-Host '[错误] 未找到 opencode 命令。' -ForegroundColor Red
  Write-Host '请先安装 OpenCode CLI 并加入 PATH，例如：'
  Write-Host '  npm install -g opencode-ai'
  Write-Host '  或按 https://opencode.ai 官方文档安装'
  exit 1
}
Write-Host "      已找到：$($oc.Source)"
Write-Host ''

# 2. 目录与密码
Write-Host "[2/5] 工作目录：$Root"
Write-Host "      服务密码：$Password"
Write-Host ''

# 3. 局域网 IP
Write-Host '[3/5] 探测本机局域网 IP...'
$lanIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object {
    $_.IPAddress -notlike '127.*' -and
    ($_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or $_.IPAddress -like '172.*')
  } |
  Select-Object -ExpandProperty IPAddress -First 1

if (-not $lanIp) {
  $lanIp = '你的电脑局域网IP'
  Write-Host '      未能自动识别，请手动查看 ipconfig 中的 IPv4。' -ForegroundColor Yellow
} else {
  Write-Host "      检测到：$lanIp"
}
Write-Host ''

# 4. 手机连接提示
Write-Host '[4/5] 手机端填写信息：'
Write-Host "      地址：http://${lanIp}:${Port}" -ForegroundColor Cyan
Write-Host "      密码：$Password" -ForegroundColor Cyan
Write-Host ''
Write-Host '      注意：手机与电脑同一局域网；防火墙放行端口' $Port
Write-Host ''

# 5. 启动
Write-Host "[5/5] 正在启动：opencode serve --port $Port --hostname $HostName"
Write-Host '      保持窗口不要关闭；按 Ctrl+C 停止。'
Write-Host '========================================'
Write-Host ''

try {
  & opencode serve --port $Port --hostname $HostName
} finally {
  Write-Host ''
  Write-Host '服务已结束。'
}
