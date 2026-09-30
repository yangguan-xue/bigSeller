# ========================================
# 大麦网可选服务启动脚本
# ========================================
# 可选服务:
# - CustomizeApplication (限流功能服务)
# - AdminApplication (监听服务)
# - MybatisPlusGenerator (代码生成器)
# ========================================

$PROJECT_ROOT = "D:\program\damai\damai"
$LOG_DIR = "$PROJECT_ROOT\logs"

# 创建日志目录
if (!(Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR | Out-Null
}

# 可选服务配置
$optionalServices = @(
    @{
        Name = "CustomizeApplication"
        Module = "damai-server/damai-customize-service"
        Port = 6084
        Description = "限流功能服务"
    },
    @{
        Name = "AdminApplication"
        Module = "damai-server/damai-admin-service"
        Port = 10082
        Description = "监听服务"
    },
    @{
        Name = "MybatisPlusGenerator"
        Module = "damai-server/damai-mybatis-plus-service"
        Port = 6088
        Description = "代码生成器"
    }
)

# 颜色输出函数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# 检查端口是否被占用
function Test-PortAvailable {
    param([int]$Port)
    $connection = $null
    try {
        $connection = [System.Net.Sockets.TcpClient]::new("localhost", $Port)
        return $false  # 端口被占用
    } catch {
        return $true   # 端口可用
    } finally {
        if ($connection) {
            $connection.Close()
        }
    }
}

# 等待端口启动
function Wait-PortReady {
    param(
        [int]$Port,
        [int]$Timeout = 60
    )
    Write-Host "  Waiting for service (port: $Port)..." -NoNewline
    $startTime = Get-Date
    while ($true) {
        if (!(Test-PortAvailable -Port $Port)) {
            Write-Host " Ready" -ForegroundColor Green
            return $true
        }
        if ((Get-Date).Subtract($startTime).TotalSeconds -gt $Timeout) {
            Write-Host " Timeout" -ForegroundColor Yellow
            return $false
        }
        Start-Sleep -Milliseconds 500
    }
}

# 启动单个服务
function Start-Service {
    param(
        [string]$ModuleName,
        [string]$ServiceName,
        [int]$Port
    )
    
    $logFile = "$LOG_DIR\$ServiceName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $modulePath = "$PROJECT_ROOT\$ModuleName"
    
    Write-Host "`nStarting service: $ServiceName" -ForegroundColor Cyan
    Write-Host "  Module path: $modulePath"
    Write-Host "  Log file: $logFile"
    
    if (!(Test-Path $modulePath)) {
        Write-ColorOutput "  Module path not found!" "Red"
        return $false
    }
    
    # 检查端口
    if (!(Test-PortAvailable -Port $Port)) {
        Write-ColorOutput "  Port $Port is already in use, please check if service is running" "Yellow"
        return $false
    }
    
    # 启动 Maven 命令
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "cmd.exe"
    $startInfo.Arguments = "/c cd /d `"$modulePath`" && mvn spring-boot:run"
    $startInfo.WorkingDirectory = $modulePath
    $startInfo.UseShellExecute = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized
    $startInfo.CreateNoWindow = $false
    
    $process = [System.Diagnostics.Process]::Start($startInfo)
    Write-ColorOutput "  Process started (PID: $($process.Id))" "Green"
    
    # 等待服务就绪
    Wait-PortReady -Port $Port -Timeout 90
    
    return $true
}

# 主程序
Write-Host "`n"
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host "       DaMai Optional Services Startup Script           " -ForegroundColor Magenta
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host "`nOptional Services:" -ForegroundColor Yellow
for ($i = 0; $i -lt $optionalServices.Count; $i++) {
    $service = $optionalServices[$i]
    Write-Host "  [$($i + 1)] $($service.Name) - $($service.Description) (Port: $($service.Port))" -ForegroundColor White
}
Write-Host "  [A] Start all optional services" -ForegroundColor White
Write-Host "  [Q] Quit" -ForegroundColor White

Write-Host "`nPlease select service(s) to start:" -ForegroundColor Yellow -NoNewline
$choice = Read-Host

if ($choice -eq 'Q' -or $choice -eq 'q') {
    Write-Host "Quitting." -ForegroundColor Gray
    exit
}

if ($choice -eq 'A' -or $choice -eq 'a') {
    # 启动全部可选服务
    Write-Host "`nStarting all optional services..." -ForegroundColor Yellow
    Write-Host "========================================================`n" -ForegroundColor Cyan
    
    foreach ($service in $optionalServices) {
        Start-Service -ModuleName $service.Module -ServiceName $service.Name -Port $service.Port
        Start-Sleep -Seconds 3
    }
} else {
    # 启动单个服务
    $index = [int]$choice - 1
    if ($index -ge 0 -and $index -lt $optionalServices.Count) {
        $service = $optionalServices[$index]
        Write-Host "`nStarting..." -ForegroundColor Yellow
        Write-Host "========================================================`n" -ForegroundColor Cyan
        Start-Service -ModuleName $service.Module -ServiceName $service.Name -Port $service.Port
    } else {
        Write-ColorOutput "Invalid selection!" "Red"
    }
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "Log directory: $LOG_DIR" -ForegroundColor Cyan
Write-Host "`n"
