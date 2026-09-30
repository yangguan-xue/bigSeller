# ========================================
# 大麦网微服务一键停止脚本
# ========================================

$services = @(
    @{Name = "BaseDataApplication"; Port = 6081},
    @{Name = "GatewayApplication"; Port = 6080},
    @{Name = "UserApplication"; Port = 6084},
    @{Name = "ProgramApplication"; Port = 6082},
    @{Name = "OrderApplication"; Port = 6083},
    @{Name = "PayApplication"; Port = 6085},
    @{Name = "CustomizeApplication"; Port = 6086},
    @{Name = "AdminApplication"; Port = 6087},
    @{Name = "MybatisPlusGenerator"; Port = 6088}
)

# 颜色输出函数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# 停止端口上的进程
function Stop-ServiceByPort {
    param([int]$Port)
    
    $processId = $null
    try {
        # 查找占用端口的进程
        $processId = (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue).OwningProcess
        if ($processId) {
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($process) {
                Write-Host "  Stopping: $($process.ProcessName) (PID: $processId)" -ForegroundColor Yellow
                Stop-Process -Id $processId -Force
                Write-Host "  Stopped" -ForegroundColor Green
                return $true
            }
        }
    } catch {
        # 如果 Get-NetTCPConnection 不可用，使用 netstat
        $output = netstat -ano | findstr ":$Port "
        if ($output) {
            $parts = $output -split '\s+'
            if ($parts.Count -ge 5) {
                $processId = $parts[-1]
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Host "  Stopping: $($process.ProcessName) (PID: $processId)" -ForegroundColor Yellow
                    Stop-Process -Id $processId -Force
                    Write-Host "  Stopped" -ForegroundColor Green
                    return $true
                }
            }
        }
    }
    
    return $false
}

# 主程序
Write-Host "`n"
Write-Host "========================================================" -ForegroundColor Red
Write-Host "       DaMai Microservices Stop Script                  " -ForegroundColor Red
Write-Host "========================================================" -ForegroundColor Red
Write-Host "`nStopping all services..." -ForegroundColor Yellow
Write-Host "========================================================`n"

$stoppedCount = 0
$notRunningCount = 0

foreach ($service in $services) {
    Write-Host "Checking: $($service.Name) (Port: $($service.Port))" -ForegroundColor Cyan
    if (Stop-ServiceByPort -Port $service.Port) {
        $stoppedCount++
    } else {
        Write-Host "  Not running" -ForegroundColor Gray
        $notRunningCount++
    }
    Start-Sleep -Milliseconds 200
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "Stop Summary:" -ForegroundColor Yellow
Write-Host "  Stopped: $stoppedCount service(s)" -ForegroundColor Green
Write-Host "  Not running: $notRunningCount service(s)" -ForegroundColor Gray
Write-Host "`n"
