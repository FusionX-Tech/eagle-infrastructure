# Keycloak Admin API Automation Script (PowerShell)
# This script provides functions to interact with Keycloak Admin API for automated configuration

param(
    [string]$KeycloakUrl = $env:KEYCLOAK_URL ?? "http://localhost:8080",
    [string]$AdminUser = $env:KEYCLOAK_ADMIN_USER ?? "admin",
    [string]$AdminPassword = $env:KEYCLOAK_ADMIN_PASSWORD ?? "admin123",
    [string]$RealmName = $env:REALM_NAME ?? "eagle-dev",
    [string]$Environment = $env:ENVIRONMENT ?? "dev",
    [string]$Action = "setup"
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeycloakDir = Split-Path -Parent $ScriptDir
$ImportDir = Join-Path $KeycloakDir "import"

# Global variables for API interaction
$script:AdminToken = ""
$script:ApiBaseUrl = ""

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

# Function to initialize API connection
function Initialize-ApiConnection {
    Write-Info "Initializing Keycloak Admin API connection..."
    
    $script:ApiBaseUrl = "$KeycloakUrl/admin/realms"
    
    # Get admin token
    $script:AdminToken = Get-AdminToken
    if (-not $script:AdminToken) {
        Write-Error "Failed to get admin token"
        return $false
    }
    
    Write-Success "Admin API connection initialized"
    return $true
}

# Function to get admin access token
function Get-AdminToken {
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

# Function to make authenticated API request
function Invoke-ApiRequest {
    param(
        [string]$Method,
        [string]$Endpoint,
        [object]$Data = $null,
        [string]$ContentType = "application/json"
    )
    
    try {
        $headers = @{ Authorization = "Bearer $script:AdminToken" }
        $uri = "$script:ApiBaseUrl/$Endpoint"
        
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $headers
        }
        
        if ($Data) {
            $params.ContentType = $ContentType
            if ($Data -is [string] -and $Data.StartsWith("@")) {
                # File reference
                $filePath = $Data.Substring(1)
                $params.Body = Get-Content -Path $filePath -Raw
            } else {
                $params.Body = $Data | ConvertTo-Json -Depth 10
            }
        }
        
        return Invoke-RestMethod @params
    }
    catch {
        Write-Error "API request failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Error "Response: $responseBody"
        }
        throw
    }
}

# Function to create or update realm
function Set-Realm {
    param([string]$RealmConfigFile)
    
    Write-Info "Creating or updating realm from $RealmConfigFile..."
    
    if (-not (Test-Path $RealmConfigFile)) {
        Write-Error "Realm configuration file not found: $RealmConfigFile"
        return $false
    }
    
    try {
        # Check if realm exists
        $realmResponse = Invoke-ApiRequest -Method "GET" -Endpoint $RealmName
        
        Write-Info "Realm $RealmName exists, updating..."
        
        # Update realm
        $realmData = Get-Content -Path $RealmConfigFile -Raw
        Invoke-ApiRequest -Method "PUT" -Endpoint $RealmName -Data $realmData
        Write-Success "Realm updated successfully"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Info "Realm $RealmName does not exist, creating..."
            
            # Create realm
            $realmData = Get-Content -Path $RealmConfigFile -Raw
            Invoke-ApiRequest -Method "POST" -Endpoint "" -Data $realmData
            Write-Success "Realm created successfully"
        } else {
            Write-Error "Failed to create or update realm: $($_.Exception.Message)"
            return $false
        }
    }
    
    return $true
}

# Function to create or update client
function Set-Client {
    param([object]$ClientConfig)
    
    $clientId = $ClientConfig.clientId
    Write-Info "Creating or updating client: $clientId"
    
    try {
        # Check if client exists
        $existingClients = Invoke-ApiRequest -Method "GET" -Endpoint "$RealmName/clients?clientId=$clientId"
        
        if ($existingClients.Count -eq 1) {
            Write-Info "Client $clientId exists, updating..."
            
            # Get client UUID
            $clientUuid = $existingClients[0].id
            
            # Update client
            Invoke-ApiRequest -Method "PUT" -Endpoint "$RealmName/clients/$clientUuid" -Data $ClientConfig
            Write-Success "Client $clientId updated successfully"
        } else {
            Write-Info "Client $clientId does not exist, creating..."
            
            # Create client
            Invoke-ApiRequest -Method "POST" -Endpoint "$RealmName/clients" -Data $ClientConfig
            Write-Success "Client $clientId created successfully"
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to create or update client $clientId`: $($_.Exception.Message)"
        return $false
    }
}

# Function to create or update realm role
function Set-RealmRole {
    param([object]$RoleConfig)
    
    $roleName = $RoleConfig.name
    Write-Info "Creating or updating realm role: $roleName"
    
    try {
        # Check if role exists
        $existingRole = Invoke-ApiRequest -Method "GET" -Endpoint "$RealmName/roles/$roleName"
        
        Write-Info "Role $roleName exists, updating..."
        
        # Update role
        Invoke-ApiRequest -Method "PUT" -Endpoint "$RealmName/roles/$roleName" -Data $RoleConfig
        Write-Success "Role $roleName updated successfully"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Info "Role $roleName does not exist, creating..."
            
            # Create role
            Invoke-ApiRequest -Method "POST" -Endpoint "$RealmName/roles" -Data $RoleConfig
            Write-Success "Role $roleName created successfully"
        } else {
            Write-Error "Failed to create or update role $roleName`: $($_.Exception.Message)"
            return $false
        }
    }
    
    return $true
}

# Function to assign roles to service account
function Set-ServiceAccountRoles {
    param(
        [string]$ClientId,
        [array]$Roles
    )
    
    Write-Info "Assigning roles to service account: $ClientId"
    
    try {
        # Get client UUID
        $clientResponse = Invoke-ApiRequest -Method "GET" -Endpoint "$RealmName/clients?clientId=$ClientId"
        $clientUuid = $clientResponse[0].id
        
        if (-not $clientUuid) {
            Write-Error "Client $ClientId not found"
            return $false
        }
        
        # Get service account user
        $serviceAccountUser = Invoke-ApiRequest -Method "GET" -Endpoint "$RealmName/clients/$clientUuid/service-account-user"
        $userId = $serviceAccountUser.id
        
        if (-not $userId) {
            Write-Error "Service account user not found for client $ClientId"
            return $false
        }
        
        # Get available realm roles
        $availableRoles = Invoke-ApiRequest -Method "GET" -Endpoint "$RealmName/users/$userId/role-mappings/realm/available"
        
        # Build role assignment payload
        $rolesToAssign = @()
        
        foreach ($roleName in $Roles) {
            $roleObj = $availableRoles | Where-Object { $_.name -eq $roleName }
            
            if ($roleObj) {
                $rolesToAssign += $roleObj
                Write-Info "Added role $roleName to assignment list"
            } else {
                Write-Warning "Role $roleName not found in available roles"
            }
        }
        
        # Assign roles
        if ($rolesToAssign.Count -gt 0) {
            Invoke-ApiRequest -Method "POST" -Endpoint "$RealmName/users/$userId/role-mappings/realm" -Data $rolesToAssign
            Write-Success "Roles assigned successfully to service account $ClientId"
        } else {
            Write-Warning "No valid roles to assign to service account $ClientId"
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to assign roles to service account $ClientId`: $($_.Exception.Message)"
        return $false
    }
}

# Function to create or update client scope
function Set-ClientScope {
    param([object]$ScopeConfig)
    
    $scopeName = $ScopeConfig.name
    Write-Info "Creating or updating client scope: $scopeName"
    
    try {
        # Check if scope exists
        $existingScopes = Invoke-ApiRequest -Method "GET" -Endpoint "$RealmName/client-scopes"
        $existingScope = $existingScopes | Where-Object { $_.name -eq $scopeName }
        
        if ($existingScope) {
            Write-Info "Client scope $scopeName exists, updating..."
            
            # Get scope ID
            $scopeId = $existingScope.id
            
            # Update scope
            Invoke-ApiRequest -Method "PUT" -Endpoint "$RealmName/client-scopes/$scopeId" -Data $ScopeConfig
            Write-Success "Client scope $scopeName updated successfully"
        } else {
            Write-Info "Client scope $scopeName does not exist, creating..."
            
            # Create scope
            Invoke-ApiRequest -Method "POST" -Endpoint "$RealmName/client-scopes" -Data $ScopeConfig
            Write-Success "Client scope $scopeName created successfully"
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to create or update client scope $scopeName`: $($_.Exception.Message)"
        return $false
    }
}

# Function to configure service accounts from configuration file
function Set-ServiceAccounts {
    param([string]$ConfigFile)
    
    Write-Info "Configuring service accounts from $ConfigFile..."
    
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Service accounts configuration file not found: $ConfigFile"
        return $false
    }
    
    try {
        $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
        
        foreach ($account in $config.serviceAccounts) {
            $clientId = $account.clientId
            $clientName = $account.clientName
            $clientSecret = $account.clientSecret
            $description = $account.description
            $assignedRoles = $account.assignedRoles
            
            # Build client configuration
            $clientConfig = @{
                clientId = $clientId
                name = $clientName
                description = $description
                enabled = $true
                publicClient = $false
                clientAuthenticatorType = "client-secret"
                secret = $clientSecret
                serviceAccountsEnabled = $true
                standardFlowEnabled = $false
                implicitFlowEnabled = $false
                directAccessGrantsEnabled = $false
                authorizationServicesEnabled = $false
                redirectUris = @()
                webOrigins = @()
                protocol = "openid-connect"
                attributes = @{
                    "access.token.lifespan" = "300"
                    "client.secret.creation.time" = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
                }
                defaultClientScopes = @("web-origins", "role_list", "profile", "roles", "email")
                optionalClientScopes = @("address", "phone", "offline_access", "microprofile-jwt", "microservice-communication")
            }
            
            # Create or update client
            if (Set-Client -ClientConfig $clientConfig) {
                # Assign roles to service account
                Set-ServiceAccountRoles -ClientId $clientId -Roles $assignedRoles
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to configure service accounts: $($_.Exception.Message)"
        return $false
    }
}

# Function to setup complete realm configuration
function Set-RealmConfiguration {
    $realmFile = Join-Path $ImportDir "eagle-realm.json"
    $serviceAccountsFile = Join-Path $ImportDir "service-accounts-config.json"
    
    Write-Info "Setting up complete realm configuration..."
    
    # Initialize API connection
    if (-not (Initialize-ApiConnection)) {
        return $false
    }
    
    # Load environment-specific configuration
    $envFile = Join-Path $ImportDir "environments" "$Environment.env"
    if (Test-Path $envFile) {
        Write-Info "Loading environment configuration: $envFile"
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
            }
        }
    }
    
    # Create or update realm
    if (-not (Set-Realm -RealmConfigFile $realmFile)) {
        return $false
    }
    
    # Wait for realm to be fully initialized
    Start-Sleep -Seconds 3
    
    # Create realm roles from realm configuration
    $realmConfig = Get-Content -Path $realmFile -Raw | ConvertFrom-Json
    foreach ($role in $realmConfig.roles.realm) {
        Set-RealmRole -RoleConfig $role
    }
    
    # Create client scopes from realm configuration
    foreach ($scope in $realmConfig.clientScopes) {
        Set-ClientScope -ScopeConfig $scope
    }
    
    # Configure service accounts
    if (-not (Set-ServiceAccounts -ConfigFile $serviceAccountsFile)) {
        return $false
    }
    
    Write-Success "Realm configuration setup completed"
    return $true
}

# Function to validate configuration
function Test-Configuration {
    Write-Info "Validating Keycloak configuration..."
    
    # Run validation script
    $validationScript = Join-Path $ScriptDir "validate-keycloak.ps1"
    if (Test-Path $validationScript) {
        & $validationScript -KeycloakUrl $KeycloakUrl -RealmName $RealmName -Environment $Environment
    } else {
        Write-Warning "Validation script not found: $validationScript"
    }
}

# Function to backup current configuration
function Backup-Configuration {
    $backupDir = Join-Path $KeycloakDir "backups"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = Join-Path $backupDir "realm-backup-$timestamp.json"
    
    Write-Info "Creating configuration backup..."
    
    # Create backup directory if it doesn't exist
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    # Initialize API connection if not already done
    if (-not $script:AdminToken) {
        Initialize-ApiConnection | Out-Null
    }
    
    try {
        # Export realm configuration
        $realmExport = Invoke-ApiRequest -Method "GET" -Endpoint $RealmName
        
        $realmExport | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8
        Write-Success "Configuration backup saved to: $backupFile"
        return $true
    }
    catch {
        Write-Error "Failed to create configuration backup: $($_.Exception.Message)"
        return $false
    }
}

# Function to show usage
function Show-Usage {
    Write-Host @"
Usage: .\keycloak-admin-api.ps1 [OPTIONS]

Options:
  -KeycloakUrl URL        Keycloak URL (default: http://localhost:8080)
  -AdminUser USER         Admin username (default: admin)
  -AdminPassword PASS     Admin password (default: admin123)
  -RealmName REALM        Realm name (default: eagle-dev)
  -Environment ENV        Environment (dev/prod) (default: dev)
  -Action ACTION          Action to perform (setup/validate/backup/help)

Actions:
  setup    - Setup complete realm configuration
  validate - Validate current configuration
  backup   - Backup current configuration
  help     - Show this help message

Examples:
  .\keycloak-admin-api.ps1 -Action setup
  .\keycloak-admin-api.ps1 -Action validate -Environment prod
  .\keycloak-admin-api.ps1 -Action backup -KeycloakUrl "https://keycloak.example.com"
"@
}

# Main execution
function Main {
    switch ($Action.ToLower()) {
        "setup" {
            Set-RealmConfiguration
        }
        "validate" {
            Test-Configuration
        }
        "backup" {
            Backup-Configuration
        }
        "help" {
            Show-Usage
        }
        default {
            Write-Error "Unknown action: $Action"
            Write-Host "Use '-Action help' for usage information"
            exit 1
        }
    }
}

# Run main function
Main