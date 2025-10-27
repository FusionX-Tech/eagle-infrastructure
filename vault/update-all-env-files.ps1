# PowerShell script to update all microservice .env files with Vault configuration

$microservices = @("ms-customer", "ms-transaction", "ms-api", "ms-enrichment", "ms-orchestrator")

Write-Host "🔐 Updating .env files for Vault integration..." -ForegroundColor Green

foreach ($service in $microservices) {
    $envFile = "eagle-backend\services\$service\.env"
    
    Write-Host "📝 Processing $service..." -ForegroundColor Yellow
    
    if (Test-Path $envFile) {
        $content = Get-Content $envFile -Raw
        
        # Check if Vault configuration already exists
        if ($content -notmatch "VAULT_ADDR") {
            # Add Vault configuration
            $vaultConfig = @"

# HashiCorp Vault Configuration
VAULT_ADDR=http://vault:8200
VAULT_ROLE_ID=
VAULT_SECRET_ID=
VAULT_DYNAMIC_DB_ENABLED=false
VAULT_REDIS_ENABLED=true
VAULT_AWS_ENABLED=true
VAULT_MANAGEMENT_ENABLED=false
"@
            
            Add-Content -Path $envFile -Value $vaultConfig
            Write-Host "  ✅ Added Vault configuration to $service" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Vault configuration already exists in $service" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ❌ .env file not found: $envFile" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "✅ All .env files updated!" -ForegroundColor Green
Write-Host "📝 Next steps:" -ForegroundColor Cyan
Write-Host "  1. Start Vault: docker-compose up -d vault" -ForegroundColor White
Write-Host "  2. Update credentials: .\infra\vault\update-env-files.sh" -ForegroundColor White
Write-Host "  3. Restart services: docker-compose restart ms-customer ms-transaction ms-api ms-enrichment ms-orchestrator" -ForegroundColor White