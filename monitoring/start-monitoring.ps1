# Eagle Alert System - Monitoring Stack Startup Script (PowerShell)
# This script starts the complete monitoring and observability stack

param(
    [switch]$SkipHealthCheck,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Eagle Alert System Monitoring Stack..." -ForegroundColor Green

# Check if Docker is running
try {
    docker info | Out-Null
} catch {
    Write-Host "❌ Docker is not running. Please start Docker first." -ForegroundColor Red
    exit 1
}

# Check if docker-compose is available
if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
    Write-Host "❌ docker-compose is not installed. Please install docker-compose first." -ForegroundColor Red
    exit 1
}

# Set environment variables if not already set
$env:GRAFANA_ADMIN_PASSWORD = if ($env:GRAFANA_ADMIN_PASSWORD) { $env:GRAFANA_ADMIN_PASSWORD } else { "admin" }
$env:GRAFANA_SECRET_KEY = if ($env:GRAFANA_SECRET_KEY) { $env:GRAFANA_SECRET_KEY } else { [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((New-Guid).ToString())) }
$env:GRAFANA_DB_PASSWORD = if ($env:GRAFANA_DB_PASSWORD) { $env:GRAFANA_DB_PASSWORD } else { "grafana123" }
$env:AWS_DEFAULT_REGION = if ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { "us-east-1" }

Write-Host "📋 Environment Configuration:" -ForegroundColor Cyan
Write-Host "  - Grafana Admin Password: $($env:GRAFANA_ADMIN_PASSWORD)" -ForegroundColor White
Write-Host "  - AWS Region: $($env:AWS_DEFAULT_REGION)" -ForegroundColor White
if ($env:SLACK_WEBHOOK_URL) { Write-Host "  - Slack Webhook: configured" -ForegroundColor White }
if ($env:PAGERDUTY_INTEGRATION_KEY) { Write-Host "  - PagerDuty: configured" -ForegroundColor White }

# Create necessary directories
Write-Host "📁 Creating necessary directories..." -ForegroundColor Yellow
$directories = @(
    ".\grafana\dashboards\system",
    ".\grafana\dashboards\business", 
    ".\grafana\dashboards\infrastructure",
    ".\grafana\dashboards\tracing",
    ".\prometheus\rules",
    ".\data\prometheus",
    ".\data\grafana",
    ".\data\alertmanager",
    ".\data\elasticsearch",
    ".\data\loki"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if ($Verbose) { Write-Host "  Created: $dir" -ForegroundColor Gray }
    }
}

# Start the monitoring stack
Write-Host "🐳 Starting monitoring containers..." -ForegroundColor Yellow
docker-compose -f docker-compose.monitoring.yml up -d

if (-not $SkipHealthCheck) {
    # Wait for services to be ready
    Write-Host "⏳ Waiting for services to start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30

    # Check service health
    Write-Host "🏥 Checking service health..." -ForegroundColor Yellow

    $services = @(
        @{name="prometheus"; port=9090},
        @{name="grafana"; port=3000},
        @{name="jaeger"; port=16686},
        @{name="loki"; port=3100},
        @{name="alertmanager"; port=9093}
    )

    foreach ($service in $services) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$($service.port)" -TimeoutSec 5 -UseBasicParsing
            Write-Host "  ✅ $($service.name) is healthy" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️  $($service.name) might not be ready yet" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "🎉 Monitoring stack started successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Access URLs:" -ForegroundColor Cyan
Write-Host "  - Grafana:      http://localhost:3000 (admin/$($env:GRAFANA_ADMIN_PASSWORD))" -ForegroundColor White
Write-Host "  - Prometheus:   http://localhost:9090" -ForegroundColor White
Write-Host "  - Jaeger:       http://localhost:16686" -ForegroundColor White
Write-Host "  - Alertmanager: http://localhost:9093" -ForegroundColor White
Write-Host "  - Loki:         http://localhost:3100" -ForegroundColor White
Write-Host ""
Write-Host "📈 Available Dashboards:" -ForegroundColor Cyan
Write-Host "  - Eagle System Overview" -ForegroundColor White
Write-Host "  - Eagle Business Metrics" -ForegroundColor White
Write-Host "  - Eagle Infrastructure Monitoring" -ForegroundColor White
Write-Host "  - Eagle Distributed Tracing" -ForegroundColor White
Write-Host ""
Write-Host "🔔 Alerting:" -ForegroundColor Cyan
Write-Host "  - Prometheus rules: .\prometheus\rules\eagle-alerts.yml" -ForegroundColor White
Write-Host "  - Alertmanager config: .\alertmanager.yml" -ForegroundColor White
Write-Host ""
Write-Host "📝 Logs:" -ForegroundColor Cyan
Write-Host "  - View container logs: docker-compose -f docker-compose.monitoring.yml logs -f [service]" -ForegroundColor White
Write-Host "  - View all logs: docker-compose -f docker-compose.monitoring.yml logs -f" -ForegroundColor White
Write-Host ""
Write-Host "🛑 To stop the stack: docker-compose -f docker-compose.monitoring.yml down" -ForegroundColor Yellow
Write-Host "🗑️  To remove all data: docker-compose -f docker-compose.monitoring.yml down -v" -ForegroundColor Red