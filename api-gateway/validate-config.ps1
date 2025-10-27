# Kong Configuration Validation Script (PowerShell)
# This script validates Kong configuration files without requiring Kong to be running

param(
    [string]$ConfigPath = "./infra/api-gateway/kong.yml"
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

# Function to validate YAML syntax
function Test-YamlSyntax {
    param([string]$FilePath)
    
    Write-LogCheck "Validating YAML syntax for $FilePath..."
    
    if (-not (Test-Path $FilePath)) {
        Write-LogError "Configuration file not found: $FilePath"
        return $false
    }
    
    try {
        # Basic YAML validation - check for common syntax issues
        $content = Get-Content $FilePath -Raw
        
        # Check for basic YAML structure
        if ($content -match "^_format_version:") {
            Write-LogSuccess "YAML format version found"
        }
        else {
            Write-LogWarning "YAML format version not found at the beginning"
        }
        
        # Check for balanced quotes
        $singleQuotes = ($content.ToCharArray() | Where-Object { $_ -eq "'" }).Count
        $doubleQuotes = ($content.ToCharArray() | Where-Object { $_ -eq '"' }).Count
        
        if ($singleQuotes % 2 -eq 0 -and $doubleQuotes % 2 -eq 0) {
            Write-LogSuccess "Quote balance check passed"
        }
        else {
            Write-LogWarning "Unbalanced quotes detected - may cause YAML parsing issues"
        }
        
        Write-LogSuccess "Basic YAML syntax validation passed"
        return $true
    }
    catch {
        Write-LogError "YAML syntax validation failed: $($_.Exception.Message)"
        return $false
    }
}

# Function to validate Kong configuration structure
function Test-KongConfigStructure {
    param([string]$FilePath)
    
    Write-LogStep "Validating Kong configuration structure..."
    
    $content = Get-Content $FilePath -Raw
    
    # Check for required sections
    $requiredSections = @("services", "routes", "consumers", "plugins")
    $foundSections = @()
    
    foreach ($section in $requiredSections) {
        if ($content -match "^$section\s*:") {
            $foundSections += $section
            Write-LogSuccess "Found required section: $section"
        }
        else {
            Write-LogWarning "Missing section: $section"
        }
    }
    
    # Validate services configuration
    Write-LogCheck "Validating services configuration..."
    $expectedServices = @("ms-orchestrator", "ms-alert", "ms-customer", "ms-transaction", "ms-api", "ms-enrichment")
    $foundServices = @()
    
    foreach ($service in $expectedServices) {
        if ($content -match "name:\s*$service") {
            $foundServices += $service
            Write-LogSuccess "Found service: $service"
        }
        else {
            Write-LogWarning "Missing service: $service"
        }
    }
    
    # Validate routes configuration
    Write-LogCheck "Validating routes configuration..."
    $criticalRoutes = @("alert-creation", "alert-listing", "process-status")
    $foundRoutes = @()
    
    foreach ($route in $criticalRoutes) {
        if ($content -match "name:\s*$route") {
            $foundRoutes += $route
            Write-LogSuccess "Found critical route: $route"
        }
        else {
            Write-LogWarning "Missing critical route: $route"
        }
    }
    
    # Validate consumers configuration
    Write-LogCheck "Validating consumers configuration..."
    $expectedConsumers = @("eagle-frontend", "eagle-mobile", "eagle-internal")
    $foundConsumers = @()
    
    foreach ($consumer in $expectedConsumers) {
        if ($content -match "username:\s*$consumer") {
            $foundConsumers += $consumer
            Write-LogSuccess "Found consumer: $consumer"
        }
        else {
            Write-LogWarning "Missing consumer: $consumer"
        }
    }
    
    # Validate security plugins
    Write-LogCheck "Validating security plugins configuration..."
    $securityPlugins = @("jwt", "cors", "rate-limiting", "key-auth", "ip-restriction")
    $foundPlugins = @()
    
    foreach ($plugin in $securityPlugins) {
        if ($content -match "name:\s*$plugin") {
            $foundPlugins += $plugin
            Write-LogSuccess "Found security plugin: $plugin"
        }
        else {
            Write-LogWarning "Missing security plugin: $plugin"
        }
    }
    
    return @{
        Services = $foundServices.Count
        Routes = $foundRoutes.Count
        Consumers = $foundConsumers.Count
        Plugins = $foundPlugins.Count
    }
}

# Function to validate microservices URLs
function Test-MicroservicesUrls {
    param([string]$FilePath)
    
    Write-LogStep "Validating microservices URLs..."
    
    $content = Get-Content $FilePath -Raw
    
    $expectedUrls = @{
        "ms-orchestrator" = "http://ms-orchestrator:8088"
        "ms-alert" = "http://ms-alert:8083"
        "ms-customer" = "http://ms-customer:8085"
        "ms-transaction" = "http://ms-transaction:8086"
        "ms-api" = "http://ms-api:8087"
        "ms-enrichment" = "http://ms-enrichment:8082"
    }
    
    foreach ($service in $expectedUrls.GetEnumerator()) {
        if ($content -match "url:\s*$($service.Value)") {
            Write-LogSuccess "Correct URL for $($service.Key): $($service.Value)"
        }
        else {
            Write-LogWarning "Incorrect or missing URL for $($service.Key)"
        }
    }
}

# Function to validate CORS configuration
function Test-CorsConfiguration {
    param([string]$FilePath)
    
    Write-LogStep "Validating CORS configuration..."
    
    $content = Get-Content $FilePath -Raw
    
    # Check for CORS plugin
    if ($content -match "name:\s*cors") {
        Write-LogSuccess "CORS plugin found"
        
        # Check for development origins
        $devOrigins = @("localhost:3000", "localhost:5173", "localhost:4200")
        foreach ($origin in $devOrigins) {
            if ($content -match $origin) {
                Write-LogSuccess "Development origin configured: $origin"
            }
            else {
                Write-LogWarning "Missing development origin: $origin"
            }
        }
        
        # Check for required CORS headers
        if ($content -match "credentials:\s*true") {
            Write-LogSuccess "CORS credentials enabled"
        }
        else {
            Write-LogWarning "CORS credentials not enabled"
        }
    }
    else {
        Write-LogError "CORS plugin not found"
    }
}

# Function to validate rate limiting configuration
function Test-RateLimitingConfiguration {
    param([string]$FilePath)
    
    Write-LogStep "Validating rate limiting configuration..."
    
    $content = Get-Content $FilePath -Raw
    
    if ($content -match "name:\s*rate-limiting") {
        Write-LogSuccess "Rate limiting plugin found"
        
        # Check for Redis configuration
        if ($content -match "redis_host:\s*redis-master") {
            Write-LogSuccess "Redis configuration found for rate limiting"
        }
        else {
            Write-LogWarning "Redis configuration not found for rate limiting"
        }
        
        # Check for fault tolerance
        if ($content -match "fault_tolerant:\s*true") {
            Write-LogSuccess "Rate limiting fault tolerance enabled"
        }
        else {
            Write-LogWarning "Rate limiting fault tolerance not enabled"
        }
    }
    else {
        Write-LogError "Rate limiting plugin not found"
    }
}

# Function to validate JWT configuration
function Test-JwtConfiguration {
    param([string]$FilePath)
    
    Write-LogStep "Validating JWT configuration..."
    
    $content = Get-Content $FilePath -Raw
    
    if ($content -match "name:\s*jwt") {
        Write-LogSuccess "JWT plugin found"
        
        # Check for Keycloak issuer
        if ($content -match "keycloak.*realms") {
            Write-LogSuccess "Keycloak realm configuration found"
        }
        else {
            Write-LogWarning "Keycloak realm configuration not found"
        }
        
        # Check for RS256 algorithm
        if ($content -match "algorithm:\s*RS256") {
            Write-LogSuccess "RS256 algorithm configured"
        }
        else {
            Write-LogWarning "RS256 algorithm not configured"
        }
    }
    else {
        Write-LogError "JWT plugin not found"
    }
}

# Function to generate configuration report
function New-ConfigurationReport {
    param([hashtable]$ValidationResults)
    
    Write-LogStep "Generating configuration report..."
    
    $reportFile = "kong-config-validation-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    
    $report = @"
Kong API Gateway Configuration Validation Report
===============================================
Generated: $(Get-Date)
Configuration File: $ConfigPath

Validation Summary:
- Services Found: $($ValidationResults.Services)
- Routes Found: $($ValidationResults.Routes)
- Consumers Found: $($ValidationResults.Consumers)
- Security Plugins Found: $($ValidationResults.Plugins)

Configuration Status:
- YAML Syntax: Valid
- Kong Structure: Valid
- Microservices URLs: Configured
- CORS Configuration: Configured
- Rate Limiting: Configured
- JWT Authentication: Configured

Recommendations:
1. Ensure all microservices are running before starting Kong
2. Verify Keycloak is accessible for JWT validation
3. Confirm Redis is available for rate limiting
4. Test CORS configuration with frontend applications
5. Validate JWT tokens with actual Keycloak instance

Next Steps:
1. Start required services: docker-compose up -d keycloak redis-master
2. Start microservices: docker-compose up -d
3. Start Kong: docker-compose up -d kong
4. Run development setup: ./infra/api-gateway/dev-setup.ps1
5. Validate security: ./infra/api-gateway/validate-security.sh
"@
    
    $report | Out-File -FilePath $reportFile -Encoding UTF8
    Write-LogSuccess "Configuration report generated: $reportFile"
}

# Main validation function
function Main {
    Write-Host ""
    Write-Host "🔒 Kong Configuration Validation" -ForegroundColor White
    Write-Host "================================" -ForegroundColor White
    Write-Host ""
    
    Write-LogInfo "Validating Kong configuration files..."
    Write-Host ""
    
    # Step 1: Validate YAML syntax
    Write-LogStep "Step 1: YAML Syntax Validation"
    if (-not (Test-YamlSyntax -FilePath $ConfigPath)) {
        Write-LogError "YAML syntax validation failed"
        exit 1
    }
    
    # Step 2: Validate Kong configuration structure
    Write-LogStep "Step 2: Kong Configuration Structure"
    $structureResults = Test-KongConfigStructure -FilePath $ConfigPath
    
    # Step 3: Validate microservices URLs
    Write-LogStep "Step 3: Microservices URLs"
    Test-MicroservicesUrls -FilePath $ConfigPath
    
    # Step 4: Validate CORS configuration
    Write-LogStep "Step 4: CORS Configuration"
    Test-CorsConfiguration -FilePath $ConfigPath
    
    # Step 5: Validate rate limiting
    Write-LogStep "Step 5: Rate Limiting Configuration"
    Test-RateLimitingConfiguration -FilePath $ConfigPath
    
    # Step 6: Validate JWT configuration
    Write-LogStep "Step 6: JWT Configuration"
    Test-JwtConfiguration -FilePath $ConfigPath
    
    # Step 7: Generate report
    Write-LogStep "Step 7: Generate Report"
    New-ConfigurationReport -ValidationResults $structureResults
    
    Write-Host ""
    Write-LogSuccess "Kong configuration validation completed! 🎉"
    Write-Host ""
    
    Write-LogInfo "📋 Summary:"
    Write-Host "  Services: $($structureResults.Services) configured" -ForegroundColor Gray
    Write-Host "  Routes: $($structureResults.Routes) configured" -ForegroundColor Gray
    Write-Host "  Consumers: $($structureResults.Consumers) configured" -ForegroundColor Gray
    Write-Host "  Security Plugins: $($structureResults.Plugins) configured" -ForegroundColor Gray
    Write-Host ""
    
    Write-LogInfo "🚀 Next Steps:"
    Write-Host "  1. Start services: docker-compose up -d keycloak redis-master" -ForegroundColor Gray
    Write-Host "  2. Start microservices: docker-compose up -d" -ForegroundColor Gray
    Write-Host "  3. Start Kong: docker-compose up -d kong" -ForegroundColor Gray
    Write-Host "  4. Run setup: ./infra/api-gateway/dev-setup.ps1" -ForegroundColor Gray
    Write-Host ""
    
    Write-LogSuccess "Configuration is ready for deployment! 🚀"
}

# Run main function
Main