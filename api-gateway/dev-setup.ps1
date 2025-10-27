# Kong API Gateway Development Setup Script (PowerShell)
# This script sets up Kong for local development with all microservices

param(
    [string]$KeycloakUrl = "http://localhost:8081",
    [string]$KeycloakRealm = "eagle-dev",
    [string]$KongAdminUrl = "http://localhost:8001",
    [string]$KongProxyUrl = "http://localhost:8080",
    [string]$RedisUrl = "redis://localhost:6379"
)

# Colors for output
$Colors = @{
    Info = "Blue"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Step = "Magenta"
    Check = "Cyan"
}

function Write-LogInfo {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $Colors.Info
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor $Colors.Success
}

function Write-LogWarning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor $Colors.Warning
}

function Write-LogError {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor $Colors.Error
}

function Write-LogStep {
    param([string]$Message)
    Write-Host "🔧 $Message" -ForegroundColor $Colors.Step
}

function Write-LogCheck {
    param([string]$Message)
    Write-Host "🔍 $Message" -ForegroundColor $Colors.Check
}

# Function to wait for service to be ready
function Wait-ForService {
    param(
        [string]$Url,
        [string]$ServiceName,
        [int]$MaxAttempts = 60
    )
    
    Write-LogInfo "Waiting for $ServiceName to be ready..."
    
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-LogSuccess "$ServiceName is ready!"
                return $true
            }
        }
        catch {
            if ($attempt % 10 -eq 0) {
                Write-LogInfo "Attempt $attempt/$MaxAttempts - $ServiceName not ready yet..."
            }
            Start-Sleep -Seconds 3
        }
    }
    
    Write-LogError "$ServiceName failed to start within expected time"
    return $false
}

# Function to check if Kong is using declarative config
function Test-KongMode {
    Write-LogCheck "Checking Kong configuration mode..."
    
    try {
        $response = Invoke-RestMethod -Uri "$KongAdminUrl/status" -Method Get -ErrorAction Stop
        
        if ($response.configuration_hash -and $response.configuration_hash -ne "none") {
            Write-LogSuccess "Kong is running in declarative mode with config hash: $($response.configuration_hash)"
            return $true
        }
        else {
            Write-LogWarning "Kong may not be using declarative configuration"
            return $false
        }
    }
    catch {
        Write-LogWarning "Kong configuration validation failed: $($_.Exception.Message)"
        return $false
    }
}

# Function to validate microservices connectivity
function Test-Microservices {
    Write-LogStep "Validating microservices connectivity..."
    
    $services = @(
        @{Name="ms-orchestrator"; Port=8088},
        @{Name="ms-alert"; Port=8083},
        @{Name="ms-customer"; Port=8085},
        @{Name="ms-transaction"; Port=8086},
        @{Name="ms-api"; Port=8087},
        @{Name="ms-enrichment"; Port=8082}
    )
    
    $failedServices = @()
    
    foreach ($service in $services) {
        Write-LogCheck "Checking $($service.Name)..."
        $healthUrl = "http://localhost:$($service.Port)/actuator/health"
        
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 5 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-LogSuccess "$($service.Name) is healthy"
            }
            else {
                Write-LogWarning "$($service.Name) returned status: $($response.StatusCode)"
                $failedServices += $service.Name
            }
        }
        catch {
            Write-LogWarning "$($service.Name) is not responding"
            $failedServices += $service.Name
        }
    }
    
    if ($failedServices.Count -eq 0) {
        Write-LogSuccess "All microservices are healthy"
        return $true
    }
    else {
        Write-LogWarning "Some microservices are not healthy: $($failedServices -join ', ')"
        Write-LogInfo "Kong will still work, but some routes may not be available"
        return $false
    }
}

# Function to test Kong routes
function Test-KongRoutes {
    Write-LogStep "Testing Kong routes..."
    
    # Test health check route (no auth required)
    Write-LogCheck "Testing health check route..."
    try {
        $response = Invoke-WebRequest -Uri "$KongProxyUrl/actuator/health" -Method Get -TimeoutSec 10 -ErrorAction Stop
        if ($response.Content -like "*UP*") {
            Write-LogSuccess "Health check route is working"
        }
        else {
            Write-LogWarning "Health check route may not be working properly"
        }
    }
    catch {
        Write-LogWarning "Health check route test failed: $($_.Exception.Message)"
    }
    
    # Test CORS preflight
    Write-LogCheck "Testing CORS configuration..."
    try {
        $headers = @{
            "Origin" = "http://localhost:3000"
            "Access-Control-Request-Method" = "POST"
            "Access-Control-Request-Headers" = "Authorization,Content-Type"
        }
        
        $response = Invoke-WebRequest -Uri "$KongProxyUrl/api/v1/alerts/create" -Method Options -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        
        if ($response.Headers["Access-Control-Allow-Origin"]) {
            Write-LogSuccess "CORS is configured correctly"
        }
        else {
            Write-LogWarning "CORS may not be configured properly"
        }
    }
    catch {
        Write-LogWarning "CORS test failed: $($_.Exception.Message)"
    }
    
    # Test rate limiting headers
    Write-LogCheck "Testing rate limiting..."
    try {
        $response = Invoke-WebRequest -Uri "$KongProxyUrl/actuator/health" -Method Get -TimeoutSec 10 -ErrorAction Stop
        
        $rateLimitHeaders = $response.Headers.Keys | Where-Object { $_ -like "*RateLimit*" }
        if ($rateLimitHeaders.Count -gt 0) {
            Write-LogSuccess "Rate limiting is active"
        }
        else {
            Write-LogInfo "Rate limiting headers not found (may be normal for health endpoints)"
        }
    }
    catch {
        Write-LogWarning "Rate limiting test failed: $($_.Exception.Message)"
    }
}

# Function to validate security headers
function Test-SecurityHeaders {
    Write-LogStep "Validating security headers..."
    
    try {
        $response = Invoke-WebRequest -Uri "$KongProxyUrl/actuator/health" -Method Get -TimeoutSec 10 -ErrorAction Stop
        
        $securityHeaders = @(
            "X-Content-Type-Options",
            "X-Frame-Options", 
            "X-XSS-Protection",
            "Strict-Transport-Security"
        )
        
        $missingHeaders = @()
        
        foreach ($header in $securityHeaders) {
            if ($response.Headers[$header]) {
                Write-LogSuccess "$header is present"
            }
            else {
                $missingHeaders += $header
            }
        }
        
        if ($missingHeaders.Count -eq 0) {
            Write-LogSuccess "All security headers are configured"
        }
        else {
            Write-LogWarning "Missing security headers: $($missingHeaders -join ', ')"
        }
    }
    catch {
        Write-LogWarning "Security headers test failed: $($_.Exception.Message)"
    }
}

# Function to check Redis connectivity
function Test-RedisConnectivity {
    Write-LogCheck "Checking Redis connectivity for rate limiting..."
    
    try {
        # Try to connect to Redis using docker exec
        $result = docker exec fx-redis-master redis-cli ping 2>$null
        if ($result -eq "PONG") {
            Write-LogSuccess "Redis is accessible via Docker"
            return $true
        }
    }
    catch {
        Write-LogWarning "Redis connectivity check failed - rate limiting may not work properly"
        return $false
    }
}

# Function to display Kong configuration summary
function Show-KongSummary {
    Write-LogStep "Kong Configuration Summary"
    Write-Host ""
    Write-Host "🌐 Kong Gateway URLs:" -ForegroundColor White
    Write-Host "  Proxy: $KongProxyUrl" -ForegroundColor Gray
    Write-Host "  Admin: $KongAdminUrl" -ForegroundColor Gray
    Write-Host ""
    Write-Host "🔐 Authentication:" -ForegroundColor White
    Write-Host "  Keycloak: $KeycloakUrl" -ForegroundColor Gray
    Write-Host "  Realm: $KeycloakRealm" -ForegroundColor Gray
    Write-Host "  JWT Issuer: $KeycloakUrl/realms/$KeycloakRealm" -ForegroundColor Gray
    Write-Host ""
    
    # Display routes
    Write-LogInfo "📍 Available Routes:"
    try {
        $routesResponse = Invoke-RestMethod -Uri "$KongAdminUrl/routes" -Method Get -ErrorAction Stop
        foreach ($route in $routesResponse.data) {
            $methods = $route.methods -join ', '
            $paths = $route.paths -join ', '
            Write-Host "  $($route.name): $methods $paths" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  Could not fetch routes information" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    # Display consumers
    Write-LogInfo "👥 Configured Consumers:"
    try {
        $consumersResponse = Invoke-RestMethod -Uri "$KongAdminUrl/consumers" -Method Get -ErrorAction Stop
        foreach ($consumer in $consumersResponse.data) {
            $customId = if ($consumer.custom_id) { "($($consumer.custom_id))" } else { "" }
            Write-Host "  $($consumer.username) $customId" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  Could not fetch consumers information" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    # Display active plugins
    Write-LogInfo "🔌 Active Plugins:"
    try {
        $pluginsResponse = Invoke-RestMethod -Uri "$KongAdminUrl/plugins" -Method Get -ErrorAction Stop
        $pluginCounts = @{}
        
        foreach ($plugin in $pluginsResponse.data) {
            $name = $plugin.name
            if ($pluginCounts.ContainsKey($name)) {
                $pluginCounts[$name]++
            }
            else {
                $pluginCounts[$name] = 1
            }
        }
        
        foreach ($plugin in $pluginCounts.GetEnumerator() | Sort-Object Name) {
            Write-Host "  $($plugin.Name): $($plugin.Value) instance(s)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  Could not fetch plugins information" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# Function to provide testing examples
function Show-TestingExamples {
    Write-Host "🧪 Testing Examples:" -ForegroundColor White
    Write-Host ""
    Write-Host "1. Health Check (No Auth):" -ForegroundColor Yellow
    Write-Host "   curl $KongProxyUrl/actuator/health" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Create Alert (Requires JWT):" -ForegroundColor Yellow
    Write-Host "   curl -X POST $KongProxyUrl/api/v1/alerts/create \" -ForegroundColor Gray
    Write-Host "        -H 'Authorization: Bearer <JWT_TOKEN>' \" -ForegroundColor Gray
    Write-Host "        -H 'Content-Type: application/json' \" -ForegroundColor Gray
    Write-Host "        -d '{`"customerDocument`":`"12345678901`",`"scopeStartDate`":`"2024-01-01`",`"scopeEndDate`":`"2024-12-31`"}'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. List Alerts (Requires JWT):" -ForegroundColor Yellow
    Write-Host "   curl $KongProxyUrl/api/v1/alerts \" -ForegroundColor Gray
    Write-Host "        -H 'Authorization: Bearer <JWT_TOKEN>'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. Test CORS:" -ForegroundColor Yellow
    Write-Host "   curl -I -X OPTIONS \" -ForegroundColor Gray
    Write-Host "        -H 'Origin: http://localhost:3000' \" -ForegroundColor Gray
    Write-Host "        -H 'Access-Control-Request-Method: POST' \" -ForegroundColor Gray
    Write-Host "        $KongProxyUrl/api/v1/alerts/create" -ForegroundColor Gray
    Write-Host ""
}

# Function to create development environment file
function New-DevEnvFile {
    Write-LogStep "Creating development environment configuration..."
    
    $envFile = "./infra/api-gateway/.env.dev"
    $envContent = @"
# Kong API Gateway Development Configuration
# Generated by dev-setup.ps1 on $(Get-Date)

# Kong URLs
KONG_ADMIN_URL=$KongAdminUrl
KONG_PROXY_URL=$KongProxyUrl

# Keycloak Configuration
KEYCLOAK_URL=$KeycloakUrl
KEYCLOAK_REALM=$KeycloakRealm
KEYCLOAK_JWT_ISSUER=$KeycloakUrl/realms/$KeycloakRealm

# Redis Configuration
REDIS_URL=$RedisUrl

# Development Settings
KONG_LOG_LEVEL=info
KONG_ADMIN_LISTEN=0.0.0.0:8001
KONG_PROXY_LISTEN=0.0.0.0:8000

# Security Settings (Development)
CORS_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:4200
RATE_LIMIT_POLICY=redis
RATE_LIMIT_FAULT_TOLERANT=true

# Monitoring
PROMETHEUS_ENABLED=true
FILE_LOG_ENABLED=true
HTTP_LOG_ENABLED=true

# Internal API Key
INTERNAL_API_KEY=eagle-internal-api-key-2024
"@
    
    $envContent | Out-File -FilePath $envFile -Encoding UTF8
    Write-LogSuccess "Development environment file created: $envFile"
}

# Main execution function
function Main {
    Write-Host ""
    Write-Host "🚀 Kong API Gateway Development Setup" -ForegroundColor White
    Write-Host "=====================================" -ForegroundColor White
    Write-Host ""
    
    Write-LogInfo "Starting Kong development setup for Eagle Alert System..."
    Write-Host ""
    
    # Step 1: Wait for required services
    Write-LogStep "Step 1: Checking service availability"
    if (-not (Wait-ForService -Url "$KongAdminUrl/status" -ServiceName "Kong Admin API")) {
        Write-LogError "Kong is not available. Please start Kong first with: docker-compose up -d kong"
        exit 1
    }
    
    if (-not (Wait-ForService -Url "$KeycloakUrl/realms/$KeycloakRealm" -ServiceName "Keycloak")) {
        Write-LogWarning "Keycloak is not available. JWT authentication may not work properly."
        Write-LogInfo "Start Keycloak with: docker-compose up -d keycloak"
    }
    
    # Step 2: Check Kong configuration mode
    Write-LogStep "Step 2: Validating Kong configuration"
    Test-KongMode | Out-Null
    
    # Step 3: Validate microservices
    Write-LogStep "Step 3: Checking microservices health"
    if (-not (Test-Microservices)) {
        Write-LogInfo "Some microservices are not available. Start them with: docker-compose up -d"
    }
    
    # Step 4: Test Kong routes
    Write-LogStep "Step 4: Testing Kong routes and plugins"
    Test-KongRoutes
    
    # Step 5: Validate security configuration
    Write-LogStep "Step 5: Validating security configuration"
    Test-SecurityHeaders
    
    # Step 6: Check Redis connectivity
    Write-LogStep "Step 6: Checking Redis connectivity"
    if (-not (Test-RedisConnectivity)) {
        Write-LogInfo "Start Redis with: docker-compose up -d redis-master"
    }
    
    # Step 7: Create development environment file
    Write-LogStep "Step 7: Creating development configuration"
    New-DevEnvFile
    
    # Step 8: Display summary
    Write-Host ""
    Write-LogSuccess "Kong API Gateway development setup completed! 🎉"
    Write-Host ""
    Show-KongSummary
    Show-TestingExamples
    
    Write-Host ""
    Write-LogInfo "📚 Additional Resources:"
    Write-Host "  Kong Admin UI: $KongAdminUrl" -ForegroundColor Gray
    Write-Host "  Kong Documentation: https://docs.konghq.com/" -ForegroundColor Gray
    Write-Host "  Keycloak Admin: $KeycloakUrl/admin" -ForegroundColor Gray
    Write-Host "  API Gateway README: ./infra/api-gateway/README.md" -ForegroundColor Gray
    Write-Host ""
    
    Write-LogSuccess "Setup completed successfully! Kong is ready for development. 🚀"
}

# Handle script interruption
trap {
    Write-LogError "Setup interrupted by user"
    exit 1
}

# Run main function
Main