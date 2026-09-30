# ========================================
# 快速启动所有后端服务
# ========================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Starting DaMai Backend Services       " -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$services = @(
    @{Name = "BaseDataApplication"; Module = "damai-server/damai-base-data-service"; Port = 6081; Delay = 0},
    @{Name = "GatewayApplication"; Module = "damai-server/damai-gateway-service"; Port = 6080; Delay = 5},
    @{Name = "ProgramApplication"; Module = "damai-server/damai-program-service"; Port = 6082; Delay = 10},
    @{Name = "UserApplication"; Module = "damai-server/damai-user-service"; Port = 6084; Delay = 15},
    @{Name = "OrderApplication"; Module = "damai-server/damai-order-service"; Port = 6083; Delay = 20},
    @{Name = "PayApplication"; Module = "damai-server/damai-pay-service"; Port = 6085; Delay = 25}
)

$PROJECT_ROOT = "D:\program\damai\damai"

foreach ($service in $services) {
    Write-Host "[$($service.Port)] Starting $($service.Name)..." -ForegroundColor Yellow
    
    $modulePath = "$PROJECT_ROOT\$($service.Module)"
    
    Start-Process cmd -ArgumentList "/k", "cd /d `"$modulePath`" && mvn spring-boot:run" -WindowStyle Minimized
    
    if ($service.Delay -gt 0) {
        Write-Host "  Waiting $($service.Delay) seconds before next service..." -ForegroundColor Gray
        Start-Sleep -Seconds $service.Delay
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " All services are starting!            " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nServices will take a few minutes to fully start." -ForegroundColor Cyan
Write-Host "You can check the status with: netstat -ano | findstr `"608"`" -ForegroundColor Gray
Write-Host "`n"
