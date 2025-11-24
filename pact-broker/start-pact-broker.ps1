# Pact Broker Startup Script (PowerShell)
# This script starts the Pact Broker infrastructure for Eagle

$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Pact Broker Infrastructure..." -ForegroundColor Cyan
Write-Host ""

# Check if Docker is running
try {
    docker info | Out-Null
    Write-Host "✅ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker is not running. Please start Docker first." -ForegroundColor Red
    exit 1
}

# Check if eagle-network exists, create if not
$networkExists = docker network inspect eagle-network 2>$null
if (-not $networkExists) {
    Write-Host "⚠️  Eagle network not found. Creating..." -ForegroundColor Yellow
    docker network create eagle-network
    Write-Host "✅ Eagle network created" -ForegroundColor Green
} else {
    Write-Host "✅ Eagle network exists" -ForegroundColor Green
}

# Load environment variables
$envFile = Join-Path $PSScriptRoot ".." ".env"
if (Test-Path $envFile) {
    Write-Host "✅ Loading environment variables from .env" -ForegroundColor Green
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([^#][^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
} else {
    Write-Host "⚠️  .env file not found. Using default values." -ForegroundColor Yellow
}

# Start services
Write-Host ""
Write-Host "📦 Starting Pact Broker services..." -ForegroundColor Cyan
docker-compose up -d

# Wait for PostgreSQL to be healthy
Write-Host ""
Write-Host "⏳ Waiting for PostgreSQL to be healthy..." -ForegroundColor Cyan
$timeout = 60
$elapsed = 0
$healthy = $false

while ($elapsed -lt $timeout) {
    try {
        $result = docker exec postgres-pact pg_isready -U fusionx 2>$null
        if ($result -match "accepting connections") {
            Write-Host "✅ PostgreSQL is healthy" -ForegroundColor Green
            $healthy = $true
            break
        }
    } catch {
        # Continue waiting
    }
    Start-Sleep -Seconds 2
    $elapsed += 2
    Write-Host "." -NoNewline
}

if (-not $healthy) {
    Write-Host ""
    Write-Host "❌ PostgreSQL failed to start within $timeout seconds" -ForegroundColor Red
    Write-Host "Check logs: docker-compose logs postgres-pact" -ForegroundColor Yellow
    exit 1
}

# Wait for Pact Broker to be healthy
Write-Host ""
Write-Host "⏳ Waiting for Pact Broker to be healthy..." -ForegroundColor Cyan
$elapsed = 0
$healthy = $false

while ($elapsed -lt $timeout) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:19292/diagnostic/status/heartbeat" -UseBasicParsing -TimeoutSec 2 2>$null
        if ($response.Content -match '"ok":true') {
            Write-Host "✅ Pact Broker is healthy" -ForegroundColor Green
            $healthy = $true
            break
        }
    } catch {
        # Continue waiting
    }
    Start-Sleep -Seconds 2
    $elapsed += 2
    Write-Host "." -NoNewline
}

if (-not $healthy) {
    Write-Host ""
    Write-Host "❌ Pact Broker failed to start within $timeout seconds" -ForegroundColor Red
    Write-Host "Check logs: docker-compose logs pact-broker" -ForegroundColor Yellow
    exit 1
}

# Display status
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✅ Pact Broker Infrastructure Started Successfully!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Services Status:" -ForegroundColor Cyan
docker-compose ps
Write-Host ""
Write-Host "🌐 Access Points:" -ForegroundColor Cyan
Write-Host "  • Pact Broker UI:  http://localhost:19292"
Write-Host "  • PostgreSQL:      localhost:5436"
Write-Host ""
Write-Host "🔐 Credentials:" -ForegroundColor Cyan
Write-Host "  • Username:        pact_user"
Write-Host "  • Password:        (check .env file)"
Write-Host ""
Write-Host "📚 Quick Commands:" -ForegroundColor Cyan
Write-Host "  • View logs:       docker-compose logs -f"
Write-Host "  • Stop services:   docker-compose down"
Write-Host "  • Restart:         docker-compose restart"
Write-Host "  • Health check:    curl http://localhost:19292/diagnostic/status/heartbeat"
Write-Host ""
Write-Host "📖 Documentation:  .\README.md" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
