# Keycloak Setup Automation Script (PowerShell)
# This script automates the setup of Keycloak realm and service accounts

param(
    [string]$KeycloakUrl = $(if ($env:KEYCLOAK_URL) { $env:KEYCLOAK_URL } else { "http://localhost:8081" }),
    [string]$AdminUser = $(if ($env:KEYCLOAK_ADMIN_USER) { $env:KEYCLOAK_ADMIN_USER } else { "admin" }),
    [string]$AdminPassword = $(if ($env:KEYCLOAK_ADMIN_PASSWORD) { $env:KEYCLOAK_ADMIN_PASSWORD } else { "admin" }),
    [string]$RealmName = $(if ($env:REALM_NAME) { $env:REALM_NAME } else { "eagle-dev" }),
    [string]$Environment = $(if ($env:ENVIRONMENT) { $env:ENVIRONMENT } else { "dev" }),
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

# Function to check if Keycloak is running
function Test-KeycloakHealth {
    Write-Info "Checking Keycloak health..."
    
    $maxAttempts = 30
    $attempt = 1
    
    while ($attempt -le $maxAttempts) {
        try {
            $response = Invoke-RestMethod -Uri "$KeycloakUrl/health/ready" -Method Get -TimeoutSec 5
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

# Function to get admin access token
function Get-AdminToken {
    Write-Info "Getting admin access token..."
    
    try {
        $body = @{
            username = $AdminUser
            password = $AdminPassword
            grant_type = "password"
            client_id = "admin-cli"
        }
        
        $response = Invoke-RestMethod -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
            -Method Post `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $body
        
        return $response.access_token
    }
    catch {
        Write-Error "Failed to get admin token: $($_.Exception.Message)"
        return $null
    }
}

# Function to check if realm exists
function Test-RealmExists {
    param(
        [string]$Token,
        [string]$Realm
    )
    
    try {
        $headers = @{ Authorization = "Bearer $Token" }
        Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/$Realm" -Method Get -Headers $headers | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Function to import realm
function Import-Realm {
    param(
        [string]$Token,
        [string]$RealmFile
    )
    
    Write-Info "Importing realm from $RealmFile..."
    
    try {
        $headers = @{ 
            Authorization = "Bearer $Token"
            "Content-Type" = "application/json"
        }
        
        $realmData = Get-Content -Path $RealmFile -Raw
        
        Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms" `
            -Method Post `
            -Headers $headers `
            -Body $realmData
        
        Write-Success "Realm imported successfully"
        return $true
    }
    catch {
        Write-Error "Failed to import realm: $($_.Exception.Message)"
        return $false
    }
}

# Function to update realm
function Update-Realm {
    param(
        [string]$Token,
        [string]$Realm,
        [string]$RealmFile
    )
    
    Write-Info "Updating realm $Realm..."
    
    try {
        $headers = @{ 
            Authorization = "Bearer $Token"
            "Content-Type" = "application/json"
        }
        
        $realmData = Get-Content -Path $RealmFile -Raw
        
        Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/$Realm" `
            -Method Put `
            -Headers $headers `
            -Body $realmData
        
        Write-Success "Realm updated successfully"
        return $true
    }
    catch {
        Write-Error "Failed to update realm: $($_.Exception.Message)"
        return $false
    }
}

# Function to validate service accounts
function Test-ServiceAccounts {
    param(
        [string]$Token,
        [string]$Realm
    )
    
    Write-Info "Validating service accounts..."
    
    try {
        $serviceAccountsConfig = Get-Content -Path "$ImportDir/service-accounts-config.json" -Raw | ConvertFrom-Json
        $headers = @{ Authorization = "Bearer $Token" }
        
        foreach ($account in $serviceAccountsConfig.serviceAccounts) {
            $clientId = $account.clientId
            Write-Info "Validating service account: $clientId"
            
            # Check if client exists
            $clientResponse = Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=$clientId" `
                -Method Get -Headers $headers
            
            if ($clientResponse.Count -eq 1) {
                Write-Success "Service account $clientId exists"
                
                # Get client UUID and check service account user
                $clientUuid = $clientResponse[0].id
                
                try {
                    $serviceAccountResponse = Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$clientUuid/service-account-user" `
                        -Method Get -Headers $headers
                    
                    Write-Success "Service account user exists: $($serviceAccountResponse.username)"
                }
                catch {
                    Write-Error "Service account user not found for $clientId"
                }
            }
            else {
                Write-Error "Service account $clientId not found or duplicated"
            }
        }
    }
    catch {
        Write-Error "Failed to validate service accounts: $($_.Exception.Message)"
    }
}

# Function to test token generation
function Test-TokenGeneration {
    param(
        [string]$Realm
    )
    
    Write-Info "Testing token generation for service accounts..."
    
    try {
        $serviceAccountsConfig = Get-Content -Path "$ImportDir/service-accounts-config.json" -Raw | ConvertFrom-Json
        
        foreach ($account in $serviceAccountsConfig.serviceAccounts) {
            $clientId = $account.clientId
            $clientSecret = $account.clientSecret
            
            Write-Info "Testing token generation for $clientId..."
            
            try {
                $body = @{
                    grant_type = "client_credentials"
                    client_id = $clientId
                    client_secret = $clientSecret
                    scope = "microservice-communication"
                }
                
                $tokenResponse = Invoke-RestMethod -Uri "$KeycloakUrl/realms/$Realm/protocol/openid-connect/token" `
                    -Method Post `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
                
                if ($tokenResponse.access_token) {
                    Write-Success "Token generation successful for $clientId"
                    
                    # Decode and display token info (basic info only)
                    $tokenParts = $tokenResponse.access_token.Split('.')
                    if ($tokenParts.Length -eq 3) {
                        try {
                            $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($tokenParts[1] + "=="))
                            $tokenData = $payload | ConvertFrom-Json
                            
                            if ($tokenData.realm_access -and $tokenData.realm_access.roles) {
                                $roles = $tokenData.realm_access.roles -join ", "
                                Write-Info "Assigned roles for $clientId`: $roles"
                            }
                        }
                        catch {
                            Write-Info "Could not decode token payload for $clientId"
                        }
                    }
                }
                else {
                    Write-Error "Token generation failed for $clientId`: No access token in response"
                }
            }
            catch {
                Write-Error "Token generation failed for $clientId`: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Error "Failed to test token generation: $($_.Exception.Message)"
    }
}

# Function to show usage
function Show-Usage {
    Write-Host @"
Usage: .\setup-keycloak.ps1 [OPTIONS]

Options:
  -KeycloakUrl URL        Keycloak URL (default: http://localhost:8080)
  -AdminUser USER         Admin username (default: admin)
  -AdminPassword PASS     Admin password (default: admin123)
  -RealmName REALM        Realm name (default: eagle-dev)
  -Environment ENV        Environment (dev/prod) (default: dev)
  -Help                   Show this help message

Environment variables:
  KEYCLOAK_URL            Keycloak URL
  KEYCLOAK_ADMIN_USER     Admin username
  KEYCLOAK_ADMIN_PASSWORD Admin password
  REALM_NAME              Realm name
  ENVIRONMENT             Environment

Examples:
  .\setup-keycloak.ps1
  .\setup-keycloak.ps1 -KeycloakUrl "https://keycloak.example.com" -Environment "prod"
"@
}

# Main execution
function Main {
    if ($Help) {
        Show-Usage
        return
    }
    
    Write-Info "Starting Keycloak setup automation..."
    Write-Info "Environment: $Environment"
    Write-Info "Keycloak URL: $KeycloakUrl"
    Write-Info "Realm: $RealmName"
    
    # Check if required files exist
    $realmFile = Join-Path $ImportDir "eagle-realm.json"
    $serviceAccountsFile = Join-Path $ImportDir "service-accounts-config.json"
    
    if (-not (Test-Path $realmFile)) {
        Write-Error "Realm configuration file not found: $realmFile"
        return
    }
    
    if (-not (Test-Path $serviceAccountsFile)) {
        Write-Error "Service accounts configuration file not found: $serviceAccountsFile"
        return
    }
    
    # Check Keycloak health
    if (-not (Test-KeycloakHealth)) {
        return
    }
    
    # Get admin token
    $adminToken = Get-AdminToken
    if (-not $adminToken) {
        Write-Error "Failed to get admin token"
        return
    }
    
    Write-Success "Admin token obtained"
    
    # Check if realm exists and import/update accordingly
    if (Test-RealmExists -Token $adminToken -Realm $RealmName) {
        Write-Warning "Realm $RealmName already exists"
        $response = Read-Host "Do you want to update the existing realm? (y/N)"
        if ($response -match "^[Yy]$") {
            Update-Realm -Token $adminToken -Realm $RealmName -RealmFile $realmFile | Out-Null
        }
        else {
            Write-Info "Skipping realm update"
        }
    }
    else {
        Import-Realm -Token $adminToken -RealmFile $realmFile | Out-Null
    }
    
    # Wait a bit for realm to be fully initialized
    Start-Sleep -Seconds 5
    
    # Validate service accounts
    Test-ServiceAccounts -Token $adminToken -Realm $RealmName
    
    # Test token generation
    Test-TokenGeneration -Realm $RealmName
    
    Write-Success "Keycloak setup completed successfully!"
    Write-Info "You can now configure your microservices to use the following endpoints:"
    Write-Info "  Token endpoint: $KeycloakUrl/realms/$RealmName/protocol/openid-connect/token"
    Write-Info "  JWKS endpoint: $KeycloakUrl/realms/$RealmName/protocol/openid-connect/certs"
    Write-Info "  Issuer URI: $KeycloakUrl/realms/$RealmName"
}

# Run main function
Main