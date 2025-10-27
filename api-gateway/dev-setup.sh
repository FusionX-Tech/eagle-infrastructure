#!/bin/bash

# Kong API Gateway Development Setup Script
# This script sets up Kong for local development with all microservices

set -e

# Configuration variables
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8081}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-eagle-dev}"
KONG_ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
KONG_PROXY_URL="${KONG_PROXY_URL:-http://localhost:8080}"
REDIS_URL="${REDIS_URL:-redis://localhost:6379}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "${PURPLE}🔧 $1${NC}"
}

log_check() {
    echo -e "${CYAN}🔍 $1${NC}"
}

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_attempts=60
    local attempt=1
    
    log_info "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            log_success "$service_name is ready!"
            return 0
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            log_info "Attempt $attempt/$max_attempts - $service_name not ready yet..."
        fi
        sleep 3
        ((attempt++))
    done
    
    log_error "$service_name failed to start within expected time"
    return 1
}

# Function to check if Kong is using declarative config
check_kong_mode() {
    log_check "Checking Kong configuration mode..."
    
    local kong_status
    kong_status=$(curl -s "${KONG_ADMIN_URL}/status" 2>/dev/null || echo "{}")
    
    local config_hash
    config_hash=$(echo "$kong_status" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('configuration_hash', 'none'))" 2>/dev/null || echo "none")
    
    if [ "$config_hash" != "none" ] && [ "$config_hash" != "null" ]; then
        log_success "Kong is running in declarative mode with config hash: $config_hash"
        return 0
    else
        log_warning "Kong may not be using declarative configuration"
        return 1
    fi
}

# Function to validate microservices connectivity
validate_microservices() {
    log_step "Validating microservices connectivity..."
    
    local services=("ms-orchestrator:8088" "ms-alert:8083" "ms-customer:8085" "ms-transaction:8086" "ms-api:8087" "ms-enrichment:8082")
    local failed_services=()
    
    for service in "${services[@]}"; do
        local service_name=$(echo "$service" | cut -d':' -f1)
        local service_port=$(echo "$service" | cut -d':' -f2)
        local health_url="http://localhost:${service_port}/actuator/health"
        
        log_check "Checking $service_name..."
        
        if curl -sf "$health_url" > /dev/null 2>&1; then
            log_success "$service_name is healthy"
        else
            log_warning "$service_name is not responding"
            failed_services+=("$service_name")
        fi
    done
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_success "All microservices are healthy"
        return 0
    else
        log_warning "Some microservices are not healthy: ${failed_services[*]}"
        log_info "Kong will still work, but some routes may not be available"
        return 1
    fi
}

# Function to test Kong routes
test_kong_routes() {
    log_step "Testing Kong routes..."
    
    # Test health check route (no auth required)
    log_check "Testing health check route..."
    local health_response
    health_response=$(curl -s "${KONG_PROXY_URL}/actuator/health" 2>/dev/null || echo "failed")
    
    if [[ "$health_response" == *"UP"* ]]; then
        log_success "Health check route is working"
    else
        log_warning "Health check route may not be working properly"
    fi
    
    # Test CORS preflight
    log_check "Testing CORS configuration..."
    local cors_response
    cors_response=$(curl -s -I -X OPTIONS \
        -H "Origin: http://localhost:3000" \
        -H "Access-Control-Request-Method: POST" \
        -H "Access-Control-Request-Headers: Authorization,Content-Type" \
        "${KONG_PROXY_URL}/api/v1/alerts/create" 2>/dev/null || echo "failed")
    
    if [[ "$cors_response" == *"Access-Control-Allow-Origin"* ]]; then
        log_success "CORS is configured correctly"
    else
        log_warning "CORS may not be configured properly"
    fi
    
    # Test rate limiting headers
    log_check "Testing rate limiting..."
    local rate_limit_response
    rate_limit_response=$(curl -s -I "${KONG_PROXY_URL}/actuator/health" 2>/dev/null || echo "failed")
    
    if [[ "$rate_limit_response" == *"X-RateLimit"* ]]; then
        log_success "Rate limiting is active"
    else
        log_info "Rate limiting headers not found (may be normal for health endpoints)"
    fi
}

# Function to validate security headers
validate_security_headers() {
    log_step "Validating security headers..."
    
    local response
    response=$(curl -s -I "${KONG_PROXY_URL}/actuator/health" 2>/dev/null || echo "failed")
    
    local security_headers=("X-Content-Type-Options" "X-Frame-Options" "X-XSS-Protection" "Strict-Transport-Security")
    local missing_headers=()
    
    for header in "${security_headers[@]}"; do
        if [[ "$response" == *"$header"* ]]; then
            log_success "$header is present"
        else
            missing_headers+=("$header")
        fi
    done
    
    if [ ${#missing_headers[@]} -eq 0 ]; then
        log_success "All security headers are configured"
    else
        log_warning "Missing security headers: ${missing_headers[*]}"
    fi
}

# Function to check Redis connectivity for rate limiting
check_redis_connectivity() {
    log_check "Checking Redis connectivity for rate limiting..."
    
    if command -v redis-cli &> /dev/null; then
        if redis-cli -h localhost -p 6379 ping > /dev/null 2>&1; then
            log_success "Redis is accessible for rate limiting"
            return 0
        fi
    fi
    
    # Try with docker if redis-cli is not available
    if docker exec fx-redis-master redis-cli ping > /dev/null 2>&1; then
        log_success "Redis is accessible via Docker"
        return 0
    fi
    
    log_warning "Redis connectivity check failed - rate limiting may not work properly"
    return 1
}

# Function to display Kong configuration summary
display_kong_summary() {
    log_step "Kong Configuration Summary"
    echo ""
    echo "🌐 Kong Gateway URLs:"
    echo "  Proxy: $KONG_PROXY_URL"
    echo "  Admin: $KONG_ADMIN_URL"
    echo ""
    echo "🔐 Authentication:"
    echo "  Keycloak: $KEYCLOAK_URL"
    echo "  Realm: $KEYCLOAK_REALM"
    echo "  JWT Issuer: ${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
    echo ""
    
    # Display routes
    log_info "📍 Available Routes:"
    local routes_info
    routes_info=$(curl -s "${KONG_ADMIN_URL}/routes" 2>/dev/null || echo '{"data":[]}')
    
    echo "$routes_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for route in data.get('data', []):
        name = route.get('name', 'unknown')
        methods = ', '.join(route.get('methods', []))
        paths = ', '.join(route.get('paths', []))
        print(f'  {name}: {methods} {paths}')
except:
    print('  Could not fetch routes information')
" 2>/dev/null || echo "  Could not fetch routes information"
    
    echo ""
    
    # Display consumers
    log_info "👥 Configured Consumers:"
    local consumers_info
    consumers_info=$(curl -s "${KONG_ADMIN_URL}/consumers" 2>/dev/null || echo '{"data":[]}')
    
    echo "$consumers_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for consumer in data.get('data', []):
        username = consumer.get('username', 'unknown')
        custom_id = consumer.get('custom_id', '')
        print(f'  {username} ({custom_id})')
except:
    print('  Could not fetch consumers information')
" 2>/dev/null || echo "  Could not fetch consumers information"
    
    echo ""
    
    # Display active plugins
    log_info "🔌 Active Plugins:"
    local plugins_info
    plugins_info=$(curl -s "${KONG_ADMIN_URL}/plugins" 2>/dev/null || echo '{"data":[]}')
    
    echo "$plugins_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    plugin_counts = {}
    for plugin in data.get('data', []):
        name = plugin.get('name', 'unknown')
        plugin_counts[name] = plugin_counts.get(name, 0) + 1
    
    for name, count in sorted(plugin_counts.items()):
        print(f'  {name}: {count} instance(s)')
except:
    print('  Could not fetch plugins information')
" 2>/dev/null || echo "  Could not fetch plugins information"
    
    echo ""
}

# Function to provide testing examples
provide_testing_examples() {
    echo "🧪 Testing Examples:"
    echo ""
    echo "1. Health Check (No Auth):"
    echo "   curl ${KONG_PROXY_URL}/actuator/health"
    echo ""
    echo "2. Create Alert (Requires JWT):"
    echo "   curl -X POST ${KONG_PROXY_URL}/api/v1/alerts/create \\"
    echo "        -H 'Authorization: Bearer <JWT_TOKEN>' \\"
    echo "        -H 'Content-Type: application/json' \\"
    echo "        -d '{\"customerDocument\":\"12345678901\",\"scopeStartDate\":\"2024-01-01\",\"scopeEndDate\":\"2024-12-31\"}'"
    echo ""
    echo "3. List Alerts (Requires JWT):"
    echo "   curl ${KONG_PROXY_URL}/api/v1/alerts \\"
    echo "        -H 'Authorization: Bearer <JWT_TOKEN>'"
    echo ""
    echo "4. Test CORS:"
    echo "   curl -I -X OPTIONS \\"
    echo "        -H 'Origin: http://localhost:3000' \\"
    echo "        -H 'Access-Control-Request-Method: POST' \\"
    echo "        ${KONG_PROXY_URL}/api/v1/alerts/create"
    echo ""
    echo "5. Check Rate Limiting:"
    echo "   for i in {1..10}; do curl -I ${KONG_PROXY_URL}/actuator/health; done"
    echo ""
}

# Function to create development environment file
create_dev_env_file() {
    log_step "Creating development environment configuration..."
    
    local env_file="./infra/api-gateway/.env.dev"
    
    cat > "$env_file" << EOF
# Kong API Gateway Development Configuration
# Generated by dev-setup.sh on $(date)

# Kong URLs
KONG_ADMIN_URL=${KONG_ADMIN_URL}
KONG_PROXY_URL=${KONG_PROXY_URL}

# Keycloak Configuration
KEYCLOAK_URL=${KEYCLOAK_URL}
KEYCLOAK_REALM=${KEYCLOAK_REALM}
KEYCLOAK_JWT_ISSUER=${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}

# Redis Configuration
REDIS_URL=${REDIS_URL}

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
EOF
    
    log_success "Development environment file created: $env_file"
}

# Main execution function
main() {
    echo ""
    echo "🚀 Kong API Gateway Development Setup"
    echo "====================================="
    echo ""
    
    log_info "Starting Kong development setup for Eagle Alert System..."
    echo ""
    
    # Step 1: Wait for required services
    log_step "Step 1: Checking service availability"
    wait_for_service "${KONG_ADMIN_URL}/status" "Kong Admin API" || {
        log_error "Kong is not available. Please start Kong first with: docker-compose up -d kong"
        exit 1
    }
    
    wait_for_service "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" "Keycloak" || {
        log_warning "Keycloak is not available. JWT authentication may not work properly."
        log_info "Start Keycloak with: docker-compose up -d keycloak"
    }
    
    # Step 2: Check Kong configuration mode
    log_step "Step 2: Validating Kong configuration"
    check_kong_mode || {
        log_warning "Kong configuration validation failed"
    }
    
    # Step 3: Validate microservices
    log_step "Step 3: Checking microservices health"
    validate_microservices || {
        log_info "Some microservices are not available. Start them with: docker-compose up -d"
    }
    
    # Step 4: Test Kong routes
    log_step "Step 4: Testing Kong routes and plugins"
    test_kong_routes
    
    # Step 5: Validate security configuration
    log_step "Step 5: Validating security configuration"
    validate_security_headers
    
    # Step 6: Check Redis connectivity
    log_step "Step 6: Checking Redis connectivity"
    check_redis_connectivity || {
        log_info "Start Redis with: docker-compose up -d redis-master"
    }
    
    # Step 7: Create development environment file
    log_step "Step 7: Creating development configuration"
    create_dev_env_file
    
    # Step 8: Display summary
    echo ""
    log_success "Kong API Gateway development setup completed! 🎉"
    echo ""
    display_kong_summary
    provide_testing_examples
    
    echo ""
    log_info "📚 Additional Resources:"
    echo "  Kong Admin UI: ${KONG_ADMIN_URL}"
    echo "  Kong Documentation: https://docs.konghq.com/"
    echo "  Keycloak Admin: ${KEYCLOAK_URL}/admin"
    echo "  API Gateway README: ./infra/api-gateway/README.md"
    echo ""
    
    log_success "Setup completed successfully! Kong is ready for development. 🚀"
}

# Handle script interruption
trap 'log_error "Setup interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"