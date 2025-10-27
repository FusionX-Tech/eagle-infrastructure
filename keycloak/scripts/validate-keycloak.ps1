# Keycloak Configuration Validation Script (PowerShell)
# This script validates the Keycloak realm and service accounts configuration

param(
    [string]$KeycloakUrl = $env:KEYCLOAK_URL ?? "http://localhost:8080",
    [string]$RealmName = $env:REALM_NAME ?? "eagle-dev",
    [string]$Environment = $env:ENVIRONMENT ?? "dev"
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeycloakDir = Split-Path -Parent $ScriptDir
$ImportDir = Join-Path $KeycloakDir "import"

# Validation results
$script:ValidationErrors = 0
$script:ValidationWarnings = 0

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
    $script:ValidationWarnings++
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" "Red"
    $script:ValidationErrors++
}

# Function to validate Keycloak connectivity
function Test-KeycloakConnectivity {
    Write-Info "Validating Keycloak connectivity..."
    
    try {
        # Test health endpoint
        Invoke-RestMethod -Uri "$KeycloakUrl/health/ready" -Method Get -TimeoutSec 10 | Out-Null
        Write-Success "Keycloak health endpoint is accessible"
    }
    catch {
        Write-Error "Keycloak health endpoint is not accessible"
        return $false
    }
    
    try {
        # Test realm endpoint
        Invoke-RestMethod -Uri "$KeycloakUrl/realms/$RealmName" -Method Get -TimeoutSec 10 | Out-Null
        Write-Success "Realm $RealmName is accessible"
    }
    catch {
        Write-Error "Realm $RealmName is not accessible"
        return $false
    }
    
    try {
        # Test JWKS endpoint
        Invoke-RestMethod -Uri "$KeycloakUrl/realms/$RealmName/protocol/openid-connect/certs" -Method Get -TimeoutSec 10 | Out-Null
        Write-Success "JWKS endpoint is accessible"
    }
    catch {
        Write-Error "JWKS endpoint is not accessible"
    }
    
    try {
        # Test token endpoint
        $response = Invoke-WebRequest -Uri "$KeycloakUrl/realms/$RealmName/protocol/openid-connect/token" -Method Post -TimeoutSec 10
        if ($response.StatusCode -eq 400) {
            Write-Success "Token endpoint is accessible"
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Success "Token endpoint is accessible"
        } else {
            Write-Error "Token endpoint is not accessible"
        }
    }
    
    return $true
}

# Function to validate realm configuration
function Test-RealmConfiguration {
    Write-Info "Validating realm configuration..."
    
    try {
        # Get realm configuration
        $realmInfo = Invoke-RestMethod -Uri "$KeycloakUrl/realms/$RealmName" -Method Get
        
        # Check realm name
        if ($realmInfo.realm -eq $RealmName) {
            Write-Success "Realm name is correct: $($realmInfo.realm)"
        } else {
            Write-Error "Realm name mismatch. Expected: $RealmName, Got: $($realmInfo.realm)"
        }
        
        # Check if realm is enabled
        if ($realmInfo.enabled -eq $true) {
            Write-Success "Realm is enabled"
        } else {
            Write-Error "Realm is not enabled"
        }
        
        # Check token lifespan
        $tokenLifespan = $realmInfo.accessTokenLifespan
        if ($tokenLifespan -gt 0 -and $tokenLifespan -le 600) {
            Write-Success "Access token lifespan is configured: ${tokenLifespan}s"
        } else {
            Write-Warning "Access token lifespan might be too long: ${tokenLifespan}s"
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to retrieve realm information: $($_.Exception.Message)"
        return $false
    }
}

# Function to validate service accounts
function Test-ServiceAccounts {
    Write-Info "Validating service accounts..."
    
    $serviceAccountsFile = Join-Path $ImportDir "service-accounts-config.json"
    if (-not (Test-Path $serviceAccountsFile)) {
        Write-Error "Service accounts configuration file not found"
        return $false
    }
    
    try {
        $config = Get-Content -Path $serviceAccountsFile -Raw | ConvertFrom-Json
        
        foreach ($account in $config.serviceAccounts) {
            $clientId = $account.clientId
            $clientSecret = $account.clientSecret
            $expectedRoles = $account.assignedRoles
            
            Write-Info "Validating service account: $clientId"
            
            # Test token generation
            try {
                $body = @{
                    grant_type = "client_credentials"
                    client_id = $clientId
                    client_secret = $clientSecret
                    scope = "microservice-communication"
                }
                
                $tokenResponse = Invoke-RestMethod -Uri "$KeycloakUrl/realms/$RealmName/protocol/openid-connect/token" `
                    -Method Post `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body $body
                
                if ($tokenResponse.access_token) {
                    Write-Success "Token generation successful for $clientId"
                    
                    # Validate token content
                    $accessToken = $tokenResponse.access_token
                    $tokenParts = $accessToken.Split('.')
                    
                    if ($tokenParts.Length -eq 3) {
                        try {
                            # Decode token payload
                            $payload = $tokenParts[1]
                            # Add padding if needed
                            while ($payload.Length % 4 -ne 0) {
                                $payload += "="
                            }
                            
                            $decodedBytes = [System.Convert]::FromBase64String($payload)
                            $decodedPayload = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
                            $tokenData = $decodedPayload | ConvertFrom-Json
                            
                            # Check token expiration
                            $exp = $tokenData.exp
                            $iat = $tokenData.iat
                            $tokenLifetime = $exp - $iat
                            
                            if ($tokenLifetime -gt 0 -and $tokenLifetime -le 600) {
                                Write-Success "Token lifetime is appropriate: ${tokenLifetime}s"
                            } else {
                                Write-Warning "Token lifetime might be inappropriate: ${tokenLifetime}s"
                            }
                            
                            # Check issuer
                            $issuer = $tokenData.iss
                            $expectedIssuer = "$KeycloakUrl/realms/$RealmName"
                            if ($issuer -eq $expectedIssuer) {
                                Write-Success "Token issuer is correct"
                            } else {
                                Write-Error "Token issuer mismatch. Expected: $expectedIssuer, Got: $issuer"
                            }
                            
                            # Check audience
                            if ($tokenData.aud) {
                                Write-Success "Token audience is present: $($tokenData.aud)"
                            } else {
                                Write-Warning "Token audience is not set"
                            }
                            
                            # Check roles
                            if ($tokenData.realm_access -and $tokenData.realm_access.roles) {
                                $tokenRoles = $tokenData.realm_access.roles
                                Write-Success "Token contains roles: $($tokenRoles -join ', ')"
                                
                                # Validate expected roles are present
                                foreach ($expectedRole in $expectedRoles) {
                                    if ($tokenRoles -contains $expectedRole) {
                                        Write-Success "Expected role '$expectedRole' is present"
                                    } else {
                                        Write-Warning "Expected role '$expectedRole' is missing"
                                    }
                                }
                            } else {
                                Write-Warning "Token does not contain realm roles"
                            }
                        }
                        catch {
                            Write-Warning "Could not decode token payload for validation: $($_.Exception.Message)"
                        }
                    }
                } else {
                    Write-Error "Token generation failed for $clientId`: No access token in response"
                }
            }
            catch {
                Write-Error "Token generation failed for $clientId`: $($_.Exception.Message)"
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to validate service accounts: $($_.Exception.Message)"
        return $false
    }
}

# Function to validate security configuration
function Test-SecurityConfiguration {
    Write-Info "Validating security configuration..."
    
    try {
        # Get realm configuration for security settings
        $realmInfo = Invoke-RestMethod -Uri "$KeycloakUrl/realms/$RealmName" -Method Get
        
        # Check SSL requirement
        $sslRequired = $realmInfo.sslRequired
        if ($sslRequired -ne "none") {
            Write-Success "SSL is required: $sslRequired"
        } else {
            Write-Warning "SSL is not required - this might be acceptable for development"
        }
        
        # Validate JWKS keys
        $jwksResponse = Invoke-RestMethod -Uri "$KeycloakUrl/realms/$RealmName/protocol/openid-connect/certs" -Method Get
        $keyCount = $jwksResponse.keys.Count
        
        if ($keyCount -gt 0) {
            Write-Success "JWKS contains $keyCount key(s)"
            
            # Check key algorithms
            $algorithms = $jwksResponse.keys | ForEach-Object { $_.alg } | Sort-Object -Unique
            Write-Info "Available key algorithms: $($algorithms -join ', ')"
            
            if ($algorithms -contains "RS256") {
                Write-Success "RS256 algorithm is available"
            } else {
                Write-Warning "RS256 algorithm is not available"
            }
        } else {
            Write-Error "No keys found in JWKS"
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to retrieve realm information for security validation: $($_.Exception.Message)"
        return $false
    }
}

# Function to validate environment-specific configuration
function Test-EnvironmentConfiguration {
    Write-Info "Validating environment-specific configuration..."
    
    $envFile = Join-Path $ImportDir "environments" "$Environment.env"
    
    if (Test-Path $envFile) {
        Write-Success "Environment configuration file exists: $envFile"
        
        # Load and validate environment variables
        $envVars = @{}
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $envVars[$matches[1]] = $matches[2]
            }
        }
        
        # Validate required environment variables
        $requiredVars = @("KEYCLOAK_REALM", "KEYCLOAK_ISSUER_URI", "MS_CUSTOMER_CLIENT_ID")
        
        foreach ($var in $requiredVars) {
            if ($envVars.ContainsKey($var) -and $envVars[$var]) {
                Write-Success "Environment variable $var is set"
            } else {
                Write-Error "Environment variable $var is not set"
            }
        }
        
        # Validate token lifespans for environment
        if ($Environment -eq "prod") {
            $accessTokenLifespan = [int]($envVars["ACCESS_TOKEN_LIFESPAN"] ?? 300)
            if ($accessTokenLifespan -le 300) {
                Write-Success "Production token lifespan is appropriately short"
            } else {
                Write-Warning "Production token lifespan might be too long"
            }
        }
    } else {
        Write-Warning "Environment configuration file not found: $envFile"
    }
}

# Function to generate validation report
function New-ValidationReport {
    Write-Info "Generating validation report..."
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportFile = Join-Path $KeycloakDir "validation-report-$timestamp.txt"
    
    $reportContent = @"
Keycloak Configuration Validation Report
========================================

Date: $(Get-Date)
Environment: $Environment
Keycloak URL: $KeycloakUrl
Realm: $RealmName

Summary:
--------
Validation Errors: $script:ValidationErrors
Validation Warnings: $script:ValidationWarnings

Status: $(if ($script:ValidationErrors -eq 0) { "PASSED" } else { "FAILED" })

Details:
--------
See console output for detailed validation results
"@
    
    $reportContent | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Info "Validation report saved to: $reportFile"
}

# Function to show usage
function Show-Usage {
    Write-Host @"
Usage: .\validate-keycloak.ps1 [OPTIONS]

Options:
  -KeycloakUrl URL        Keycloak URL (default: http://localhost:8080)
  -RealmName REALM        Realm name (default: eagle-dev)
  -Environment ENV        Environment (dev/prod) (default: dev)

Environment variables:
  KEYCLOAK_URL            Keycloak URL
  REALM_NAME              Realm name
  ENVIRONMENT             Environment

Examples:
  .\validate-keycloak.ps1
  .\validate-keycloak.ps1 -KeycloakUrl "https://keycloak.example.com" -Environment "prod"
"@
}

# Main execution
function Main {
    Write-Info "Starting Keycloak configuration validation..."
    Write-Info "Environment: $Environment"
    Write-Info "Keycloak URL: $KeycloakUrl"
    Write-Info "Realm: $RealmName"
    
    Write-Host "========================================"
    
    # Run validations
    Test-KeycloakConnectivity
    Test-RealmConfiguration
    Test-ServiceAccounts
    Test-SecurityConfiguration
    Test-EnvironmentConfiguration
    
    Write-Host "========================================"
    
    # Generate report
    New-ValidationReport
    
    # Final summary
    Write-Info "Validation completed"
    Write-Info "Errors: $script:ValidationErrors"
    Write-Info "Warnings: $script:ValidationWarnings"
    
    if ($script:ValidationErrors -eq 0) {
        Write-Success "All validations passed!"
        if ($script:ValidationWarnings -gt 0) {
            Write-Warning "There are $script:ValidationWarnings warning(s) that should be reviewed"
        }
        exit 0
    } else {
        Write-Error "Validation failed with $script:ValidationErrors error(s)"
        exit 1
    }
}

# Run main function
Main