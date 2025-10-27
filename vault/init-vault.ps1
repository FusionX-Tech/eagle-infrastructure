# PowerShell script to initialize HashiCorp Vault

Write-Host "🔐 Initializing HashiCorp Vault..." -ForegroundColor Green

# Start Vault container
Write-Host "🚀 Starting Vault container..." -ForegroundColor Yellow
docker-compose -f eagle-backend\docker-compose.yml up -d vault

# Wait for Vault to be ready
Write-Host "⏳ Waiting for Vault to be ready..." -ForegroundColor Yellow
$maxAttempts = 30
$attempt = 0

do {
    $attempt++
    Start-Sleep -Seconds 2
    
    try {
        $status = docker exec fx-vault vault status 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Vault is ready!" -ForegroundColor Green
            break
        }
    } catch {
        # Continue waiting
    }
    
    if ($attempt -ge $maxAttempts) {
        Write-Host "❌ Timeout waiting for Vault to be ready" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  Attempt $attempt/$maxAttempts - Vault not ready yet..." -ForegroundColor Gray
} while ($true)

# Check if Vault is already initialized
Write-Host "🔍 Checking Vault initialization status..." -ForegroundColor Yellow

try {
    $vaultStatus = docker exec fx-vault vault status -format=json 2>$null | ConvertFrom-Json
    
    if ($vaultStatus.initialized -eq $true) {
        Write-Host "✅ Vault is already initialized!" -ForegroundColor Green
        
        # Get AppRole credentials
        Write-Host "📋 Retrieving AppRole credentials..." -ForegroundColor Yellow
        
        $roleId = docker exec fx-vault vault read -field=role_id auth/approle/role/microservices-role/role-id 2>$null
        $secretId = docker exec fx-vault vault write -field=secret_id auth/approle/role/microservices-role/secret-id 2>$null
        
        if ($roleId -and $secretId) {
            Write-Host "✅ Retrieved Vault credentials successfully" -ForegroundColor Green
            Write-Host "📋 Role ID: $roleId" -ForegroundColor Cyan
            Write-Host "🔐 Secret ID: $secretId" -ForegroundColor Cyan
            
            # Update .env files with credentials
            Write-Host "📝 Updating .env files with Vault credentials..." -ForegroundColor Yellow
            
            $microservices = @("ms-alert", "ms-customer", "ms-transaction", "ms-api", "ms-enrichment", "ms-orchestrator")
            
            foreach ($service in $microservices) {
                $envFile = "eagle-backend\services\$service\.env"
                
                if (Test-Path $envFile) {
                    $content = Get-Content $envFile
                    $content = $content -replace "VAULT_ROLE_ID=.*", "VAULT_ROLE_ID=$roleId"
                    $content = $content -replace "VAULT_SECRET_ID=.*", "VAULT_SECRET_ID=$secretId"
                    $content | Set-Content $envFile
                    Write-Host "  ✅ Updated $service" -ForegroundColor Green
                }
            }
            
            # Update main .env file
            $mainEnvFile = "eagle-backend\.env"
            if (Test-Path $mainEnvFile) {
                $content = Get-Content $mainEnvFile
                
                # Add Vault configuration if not exists
                if ($content -notmatch "VAULT_ADDR") {
                    $vaultConfig = @"

# HashiCorp Vault Configuration
VAULT_ADDR=http://vault:8200
VAULT_ROOT_TOKEN=myroot
VAULT_ROLE_ID=$roleId
VAULT_SECRET_ID=$secretId
"@
                    Add-Content -Path $mainEnvFile -Value $vaultConfig
                } else {
                    $content = $content -replace "VAULT_ROLE_ID=.*", "VAULT_ROLE_ID=$roleId"
                    $content = $content -replace "VAULT_SECRET_ID=.*", "VAULT_SECRET_ID=$secretId"
                    $content | Set-Content $mainEnvFile
                }
                Write-Host "  ✅ Updated main .env file" -ForegroundColor Green
            }
            
        } else {
            Write-Host "❌ Failed to retrieve Vault credentials" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "⚠️  Vault is not initialized. It should auto-initialize in dev mode." -ForegroundColor Yellow
        Write-Host "Please check Vault logs: docker logs fx-vault" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "❌ Error checking Vault status: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🎉 Vault initialization completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "🔐 Vault Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Vault URL: http://localhost:8200" -ForegroundColor White
Write-Host "  Root Token: myroot" -ForegroundColor White
Write-Host "  Role ID: $roleId" -ForegroundColor White
Write-Host "  Secret ID: $secretId" -ForegroundColor White
Write-Host ""
Write-Host "📝 Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart microservices: docker-compose restart ms-alert ms-customer ms-transaction ms-api ms-enrichment ms-orchestrator" -ForegroundColor White
Write-Host "  2. Verify Vault connectivity: curl http://localhost:8083/actuator/health/vault" -ForegroundColor White
Write-Host "  3. Access Vault UI: http://localhost:8200 (token: myroot)" -ForegroundColor White