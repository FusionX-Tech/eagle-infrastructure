# Eagle Alert System - Monitoring Stack Stop Script (PowerShell)
# This script stops the complete monitoring and observability stack

param(
    [switch]$RemoveData,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "🛑 Stopping Eagle Alert System Monitoring Stack..." -ForegroundColor Yellow

# Check if docker-compose is available
if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
    Write-Host "❌ docker-compose is not installed." -ForegroundColor Red
    exit 1
}

if ($RemoveData) {
    if (-not $Force) {
        $confirmation = Read-Host "⚠️  This will remove all monitoring data (metrics, logs, dashboards). Are you sure? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-Host "❌ Operation cancelled." -ForegroundColor Red
            exit 0
        }
    }
    
    Write-Host "🗑️  Stopping containers and removing volumes..." -ForegroundColor Red
    docker-compose -f docker-compose.monitoring.yml down -v
    
    # Remove data directories
    $dataDirectories = @(
        ".\data\prometheus",
        ".\data\grafana", 
        ".\data\alertmanager",
        ".\data\elasticsearch",
        ".\data\loki"
    )
    
    foreach ($dir in $dataDirectories) {
        if (Test-Path $dir) {
            Remove-Item -Path $dir -Recurse -Force
            Write-Host "  Removed: $dir" -ForegroundColor Gray
        }
    }
    
    Write-Host "✅ Monitoring stack stopped and all data removed." -ForegroundColor Green
} else {
    Write-Host "🛑 Stopping containers..." -ForegroundColor Yellow
    docker-compose -f docker-compose.monitoring.yml down
    
    Write-Host "✅ Monitoring stack stopped. Data preserved." -ForegroundColor Green
    Write-Host "💡 To remove all data, use: .\stop-monitoring.ps1 -RemoveData" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "📊 To restart the stack: .\start-monitoring.ps1" -ForegroundColor Cyan