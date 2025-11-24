# Pact Broker Stop Script (PowerShell)
# This script stops the Pact Broker infrastructure

$ErrorActionPreference = "Stop"

Write-Host "🛑 Stopping Pact Broker Infrastructure..." -ForegroundColor Cyan
Write-Host ""

# Stop services
docker-compose down

Write-Host ""
Write-Host "✅ Pact Broker Infrastructure Stopped" -ForegroundColor Green
Write-Host ""
Write-Host "To remove volumes (delete all data), run:" -ForegroundColor Yellow
Write-Host "  docker-compose down -v"
