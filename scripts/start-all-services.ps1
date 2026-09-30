# ========================================
# 大麦网微服务一键启动脚本
# ========================================
# 启动顺序:
# 1. BaseDataApplication (基础数据服务 - 必须第一个启动)
# 2. GatewayApplication (网关服务)
# 3. UserApplication (用户服务)
# 4. ProgramApplication (节目服务)
# 5. OrderApplication (订单服务)
# 6. PayApplication (支付服务)
# ========================================

$PROJECT_ROOT = "D:\program\damai\damai"
$LOG_DIR = "$PROJECT_ROOT\logs"

# 创建日志目录
if (!(Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR | Out-Null
}

# 服务配置列表
$services = @(
    @{
        Name = "BaseDataApplication"
        Module = "damai-server/damai-base-data-service"
        Port = 6083
        Priority = 1
        Required = $true
        Description = "基础数据服务 (必须第一个启动)"
    },
    @{
        Name = "GatewayApplication"
        Module = "damai-server/damai-gateway-service"
        Port = 6085
        Priority = 2
        Required = $true
        Description = "网关服务"
    },
    @{
        Name = "UserApplication"
        Module = "damai-server/damai-user-service"
        Port = 6082
        Priority = 3
        Required = $true
        Description = "用户服务"
    },
    @{
        Name = "ProgramApplication"
        Module = "damai-server/damai-program-service"
        Port = 6086
        Priority = 4
        Required = $true
        Description = "节目服务"
    },
    @{
        Name = "OrderApplication"
        Module = "damai-server/damai-order-service"
        Port = 8081
        Priority = 5
        Required = $true
        Description = "订单服务"
    },
    @{
        Name = "PayApplication"
        Module = "damai-server/damai-pay-service"
        Port = 6087
        Priority = 6
        Required = $true
        Description = "支付服务"
    }
)

# 可选服务 (不自动启动)
$optionalServices = @(
    @{
        Name = "CustomizeApplication"
        Module = "damai-server/damai-customize-service"
        Port = 6084
        Description = "限流功能服务 (可选)"
    },
    @{
        Name = "AdminApplication"
        Module = "damai-server/damai-admin-service"
        Port = 10082
        Description = "监听服务 (可选)"
    },
    @{
        Name = "MybatisPlusGenerator"
        Module = "damai-server/damai-mybatis-plus-service"
        Port = 6088
        Description = "代码生成器 (可选)"
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
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "       DaMai Microservices One-Click Startup Script     " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "`nStartup Plan:" -ForegroundColor Yellow
Write-Host "  Required Services:" -ForegroundColor Green
foreach ($service in $services) {
    Write-Host "    $($service.Priority). $($service.Name) - $($service.Description)" -ForegroundColor White
}
Write-Host "`n  Optional Services (not auto-started):" -ForegroundColor Gray
foreach ($service in $optionalServices) {
    Write-Host "    - $($service.Name) - $($service.Description)" -ForegroundColor Gray
}

Write-Host "`nStarting..." -ForegroundColor Yellow
Write-Host "========================================================`n" -ForegroundColor Cyan

# 按优先级排序并启动必选服务
$sortedServices = $services | Sort-Object -Property Priority
$successCount = 0
$failCount = 0

foreach ($service in $sortedServices) {
    if (Start-Service -ModuleName $service.Module -ServiceName $service.Name -Port $service.Port) {
        $successCount++
    } else {
        $failCount++
        if ($service.Required) {
            Write-ColorOutput "`nCritical service failed to start. Continue? (Y/N)" "Yellow"
            $response = Read-Host
            if ($response -ne 'Y' -and $response -ne 'y') {
                break
            }
        }
    }
    
    # 服务间延迟，避免资源竞争
    if ($service.Priority -lt $services.Count) {
        Write-Host "  Waiting 3 seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }
}

# 输出总结
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "Startup Summary:" -ForegroundColor Yellow
Write-Host "  Success: $successCount service(s)" -ForegroundColor Green
Write-Host "  Failed: $failCount service(s)" -ForegroundColor Red
Write-Host "`nLog directory: $LOG_DIR" -ForegroundColor Cyan
Write-Host "`nTips:" -ForegroundColor Yellow
Write-Host "  - For optional services, run mvn spring-boot:run in respective module" -ForegroundColor Gray
Write-Host "  - View logs: Get-ChildItem $LOG_DIR | Sort-Object LastWriteTime -Descending" -ForegroundColor Gray
Write-Host "`n"
