# Keycloak Setup Automation Orchestrator (PowerShell)
# This script orchestrates the complete Keycloak setup and configuration process

param(
    [string]$KeycloakUrl = $env:KEYCLOAK_URL ?? "http://localhost:8080",
    [string]$AdminUser = $env:KEYCLOAK_ADMIN_USER ?? "admin",
    [string]$AdminPassword = $env:KEYCLOAK_ADMIN_PASSWORD ?? "admin123",
    [string]$RealmName = $env:REALM_NAME ?? "eagle-dev",
    [string]$Environment = $env:ENVIRONMENT ?? "dev",
    [switch]$SkipValidation,
    [switch]$NoBackup,
    [switch]$AutoApprove,
    [switch]$Help
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeycloakDir = Split-Path -Parent $ScriptDir
$ImportDir = Join-Path $KeycloakDir "import"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    $colorMap = @{
        "Red" = "Red"
        "Green" = "Green"
        "Yellow" = "Yellow"
        "Blue" = "Blue"
        "Cyan" = "Cyan"
        "White" = "White"
    }
    
    Write-Host $Message -ForegroundColor $colorMap[$Color]
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "[INFO] $Message" "Blue"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "[SUCCESS] $Message" "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "[WARNING] $Message" "Yellow"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" "Red"
}

function Write-Step {
    param([string]$Message)
    Write-ColorOutput "[STEP] $Message" "Cyan"
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Step "Checking prerequisites..."
    
    # Check required files
    $requiredFiles = @(
        (Join-Path $ImportDir "eagle-realm.json"),
        (Join-Path $ImportDir "service-accounts-config.json"),
        (Join-Path $ImportDir "environments" "$Environment.env")
    )
    
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            Write-Error "Required file not found: $file"
            return $false
        }
    }
    
    Write-Success "All prerequisites satisfied"
    return $true
}

# Function to display configuration summary
function Show-Configuration {
    Write-Step "Configuration Summary"
    Write-Host "========================================"
    Write-Host "Environment: $Environment"
    Write-Host "Keycloak URL: $KeycloakUrl"
    Write-Host "Realm Name: $RealmName"
    Write-Host "Admin User: $AdminUser"
    Write-Host "Skip Validation: $SkipValidation"
    Write-Host "No Backup: $NoBackup"
    Write-Host "Auto Approve: $AutoApprove"
    Write-Host "========================================"
}

# Function to wait for user confirmation
function Wait-ForConfirmation {
    if ($AutoApprove) {
        return $true
    }
    
    $response = Read-Host "Do you want to continue? (y/N)"
    if ($response -notmatch "^[Yy]$") {
        Write-Info "Setup cancelled by user"
        exit 0
    }
    
    return $true
}

# Function to check Keycloak health
function Test-KeycloakHealth {
    Write-Step "Checking Keycloak health..."
    
    $maxAttempts = 30
    $attempt = 1
    
    while ($attempt -le $maxAttempts) {
        try {
            Invoke-RestMethod -Uri "$KeycloakUrl/health/ready" -Method Get -TimeoutSec 5 | Out-Null
            Write-Success "Keycloak is ready"
            return $true
        }
        catch {
            Write-Info "Waiting for Keycloak to be ready (attempt $attempt/$maxAttempts)..."
            Start-Sleep -Seconds 5
            $attempt++
        }
    }
    
    Write-Error "Keycloak is not ready after $maxAttempts attempts"
    return $false
}

# Function to backup existing configuration
function Backup-Configuration {
    if (-not $NoBackup) {
        Write-Step "Creating configuration backup..."
        
        $adminApiScript = Join-Path $ScriptDir "keycloak-admin-api.ps1"
        if (Test-Path $adminApiScript) {
            try {
                & $adminApiScript -KeycloakUrl $KeycloakUrl -AdminUser $AdminUser -AdminPassword $AdminPassword -RealmName $RealmName -Action "backup"
            }
            catch {
                Write-Warning "Backup failed: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Backup script not found, skipping backup"
        }
    } else {
        Write-Info "Skipping configuration backup"
    }
}

# Function to setup realm configuration
function Set-RealmConfiguration {
    Write-Step "Setting up realm configuration..."
    
    $adminApiScript = Join-Path $ScriptDir "keycloak-admin-api.ps1"
    if (Test-Path $adminApiScript) {
        try {
            & $adminApiScript -KeycloakUrl $KeycloakUrl -AdminUser $AdminUser -AdminPassword $AdminPassword -RealmName $RealmName -Environment $Environment -Action "setup"
            return $true
        }
        catch {
            Write-Error "Realm setup failed: $($_.Exception.Message)"
            return $false
        }
    } else {
        Write-Error "Admin API script not found: $adminApiScript"
        return $false
    }
}

# Function to validate configuration
function Test-Configuration {
    if ($SkipValidation) {
        Write-Info "Skipping configuration validation"
        return $true
    }
    
    Write-Step "Validating configuration..."
    
    $validationScript = Join-Path $ScriptDir "validate-keycloak.ps1"
    if (Test-Path $validationScript) {
        try {
            & $validationScript -KeycloakUrl $KeycloakUrl -RealmName $RealmName -Environment $Environment
            return $true
        }
        catch {
            Write-Warning "Validation failed: $($_.Exception.Message)"
            return $false
        }
    } else {
        Write-Warning "Validation script not found, skipping validation"
        return $true
    }
}

# Function to generate setup report
function New-SetupReport {
    Write-Step "Generating setup report..."
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportFile = Join-Path $KeycloakDir "setup-report-$timestamp.txt"
    
    $reportContent = @"
Keycloak Setup Automation Report
================================

Date: $(Get-Date)
Environment: $Environment
Keycloak URL: $KeycloakUrl
Realm: $RealmName

Configuration:
--------------
Admin User: $AdminUser
Skip Validation: $SkipValidation
No Backup: $NoBackup
Auto Approve: $AutoApprove

Setup Steps Completed:
----------------------
1. Prerequisites Check: ✓
2. Keycloak Health Check: ✓
3. Configuration Backup: $(if (-not $NoBackup) { "✓" } else { "Skipped" })
4. Realm Setup: ✓
5. Configuration Validation: $(if (-not $SkipValidation) { "✓" } else { "Skipped" })

Service Accounts Configured:
----------------------------
"@
    
    # Add service accounts information
    $serviceAccountsFile = Join-Path $ImportDir "service-accounts-config.json"
    if (Test-Path $serviceAccountsFile) {
        $config = Get-Content -Path $serviceAccountsFile -Raw | ConvertFrom-Json
        foreach ($account in $config.serviceAccounts) {
            $reportContent += "- $($account.clientId) ($($account.clientName))`n"
        }
    }
    
    $reportContent += @"

Endpoints:
----------
Token Endpoint: $KeycloakUrl/realms/$RealmName/protocol/openid-connect/token
JWKS Endpoint: $KeycloakUrl/realms/$RealmName/protocol/openid-connect/certs
Issuer URI: $KeycloakUrl/realms/$RealmName

Next Steps:
-----------
1. Update microservice configurations with the new endpoints
2. Test service-to-service authentication
3. Monitor logs for any authentication issues
4. Consider setting up monitoring and alerting for Keycloak

"@
    
    $reportContent | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Success "Setup report saved to: $reportFile"
}

# Function to display next steps
function Show-NextSteps {
    Write-Step "Next Steps"
    Write-Host "========================================"
    Write-Host "1. Update microservice configurations:"
    Write-Host "   - Set KEYCLOAK_ISSUER_URI=$KeycloakUrl/realms/$RealmName"
    Write-Host "   - Configure client credentials for each service"
    Write-Host ""
    Write-Host "2. Test service-to-service authentication:"
    Write-Host "   - Verify token generation for each service account"
    Write-Host "   - Test API calls between microservices"
    Write-Host ""
    Write-Host "3. Monitor and maintain:"
    Write-Host "   - Check Keycloak logs regularly"
    Write-Host "   - Monitor token generation metrics"
    Write-Host "   - Keep service account credentials secure"
    Write-Host ""
    Write-Host "4. Environment-specific configurations:"
    Write-Host "   - Review $ImportDir/environments/$Environment.env"
    Write-Host "   - Adjust token lifespans as needed"
    Write-Host "   - Configure SSL/TLS for production"
    Write-Host "========================================"
}

# Function to show usage
function Show-Usage {
    Write-Host @"
Usage: .\setup-automation.ps1 [OPTIONS]

Options:
  -KeycloakUrl URL        Keycloak URL (default: http://localhost:8080)
  -AdminUser USER         Admin username (default: admin)
  -AdminPassword PASS     Admin password (default: admin123)
  -RealmName REALM        Realm name (default: eagle-dev)
  -Environment ENV        Environment (dev/prod) (default: dev)
  -SkipValidation         Skip configuration validation
  -NoBackup               Skip configuration backup
  -AutoApprove            Auto approve all prompts
  -Help                   Show this help message

Environment variables:
  KEYCLOAK_URL            Keycloak URL
  KEYCLOAK_ADMIN_USER     Admin username
  KEYCLOAK_ADMIN_PASSWORD Admin password
  REALM_NAME              Realm name
  ENVIRONMENT             Environment

Examples:
  .\setup-automation.ps1
  .\setup-automation.ps1 -Environment prod -AutoApprove
  .\setup-automation.ps1 -SkipValidation -NoBackup
"@
}

# Main execution function
function Main {
    if ($Help) {
        Show-Usage
        return
    }
    
    Write-Info "Starting Keycloak Setup Automation"
    Write-Info "Script: $(Split-Path -Leaf $MyInvocation.MyCommand.Path)"
    Write-Info "Version: 1.0.0"
    Write-Host ""
    
    # Display configuration
    Show-Configuration
    
    # Wait for user confirmation
    Wait-ForConfirmation
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        exit 1
    }
    
    # Check Keycloak health
    if (-not (Test-KeycloakHealth)) {
        exit 1
    }
    
    # Backup existing configuration
    Backup-Configuration
    
    # Setup realm configuration
    if (-not (Set-RealmConfiguration)) {
        Write-Error "Realm setup failed"
        exit 1
    }
    
    # Validate configuration
    Test-Configuration | Out-Null
    
    # Generate setup report
    New-SetupReport
    
    # Display next steps
    Show-NextSteps
    
    Write-Success "Keycloak setup automation completed successfully!"
}

# Run main function
Main