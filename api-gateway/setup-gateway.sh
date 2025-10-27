#!/bin/bash

# API Gateway Setup Script
# This script sets up Kong API Gateway with Keycloak integration and security policies

set -e

echo "🚀 Setting up API Gateway with Kong..."

# Configuration variables
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8081}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-eagle-dev}"
KONG_ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
KONG_PROXY_URL="${KONG_PROXY_URL:-http://localhost:8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            log_success "$service_name is ready!"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts - $service_name not ready yet..."
        sleep 5
        ((attempt++))
    done
    
    log_error "$service_name failed to start within expected time"
    return 1
}

# Function to fetch Keycloak public key
fetch_keycloak_public_key() {
    log_info "Fetching Keycloak public key..."
    
    local public_key_response
    public_key_response=$(curl -s "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to fetch Keycloak realm information"
        return 1
    fi
    
    # Extract public key using jq or python
    if command -v jq &> /dev/null; then
        KEYCLOAK_PUBLIC_KEY=$(echo "$public_key_response" | jq -r '.public_key')
    else
        # Fallback to python if jq is not available
        KEYCLOAK_PUBLIC_KEY=$(echo "$public_key_response" | python3 -c "import sys, json; print(json.load(sys.stdin)['public_key'])")
    fi
    
    if [ -z "$KEYCLOAK_PUBLIC_KEY" ] || [ "$KEYCLOAK_PUBLIC_KEY" = "null" ]; then
        log_error "Failed to extract public key from Keycloak"
        return 1
    fi
    
    log_success "Keycloak public key fetched successfully"
    return 0
}

# Function to configure Kong JWT
configure_kong_jwt() {
    log_info "Configuring Kong JWT authentication..."
    
    local public_key_pem="-----BEGIN PUBLIC KEY-----\n${KEYCLOAK_PUBLIC_KEY}\n-----END PUBLIC KEY-----"
    local issuer="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
    
    # Configure JWT for eagle-frontend consumer
    log_info "Setting up JWT for eagle-frontend..."
    curl -X POST "${KONG_ADMIN_URL}/consumers/eagle-frontend/jwt" \
        -H "Content-Type: application/json" \
        -d "{
            \"key\": \"${issuer}\",
            \"algorithm\": \"RS256\",
            \"rsa_public_key\": \"${public_key_pem}\"
        }" 2>/dev/null || log_warning "JWT credential for eagle-frontend may already exist"
    
    # Configure JWT for eagle-mobile consumer
    log_info "Setting up JWT for eagle-mobile..."
    curl -X POST "${KONG_ADMIN_URL}/consumers/eagle-mobile/jwt" \
        -H "Content-Type: application/json" \
        -d "{
            \"key\": \"${issuer}\",
            \"algorithm\": \"RS256\",
            \"rsa_public_key\": \"${public_key_pem}\"
        }" 2>/dev/null || log_warning "JWT credential for eagle-mobile may already exist"
    
    log_success "Kong JWT authentication configured"
}

# Function to configure API keys for internal services
configure_api_keys() {
    log_info "Configuring API keys for internal services..."
    
    curl -X POST "${KONG_ADMIN_URL}/consumers/eagle-internal/key-auth" \
        -H "Content-Type: application/json" \
        -d "{
            \"key\": \"eagle-internal-api-key-2024\"
        }" 2>/dev/null || log_warning "API key for eagle-internal may already exist"
    
    log_success "API keys configured"
}

# Function to verify Kong configuration
verify_kong_configuration() {
    log_info "Verifying Kong configuration..."
    
    # Check Kong status
    local kong_status
    kong_status=$(curl -s "${KONG_ADMIN_URL}/status" | python3 -c "import sys, json; print(json.load(sys.stdin)['database']['reachable'])" 2>/dev/null || echo "false")
    
    if [ "$kong_status" != "true" ]; then
        log_error "Kong database is not reachable"
        return 1
    fi
    
    # Check routes
    local routes_count
    routes_count=$(curl -s "${KONG_ADMIN_URL}/routes" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null || echo "0")
    
    if [ "$routes_count" -eq 0 ]; then
        log_error "No routes configured in Kong"
        return 1
    fi
    
    # Check consumers
    local consumers_count
    consumers_count=$(curl -s "${KONG_ADMIN_URL}/consumers" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null || echo "0")
    
    if [ "$consumers_count" -eq 0 ]; then
        log_error "No consumers configured in Kong"
        return 1
    fi
    
    log_success "Kong configuration verified successfully"
    return 0
}

# Function to display configuration summary
display_summary() {
    echo ""
    echo "📋 API Gateway Configuration Summary"
    echo "=================================="
    echo "Kong Proxy URL: $KONG_PROXY_URL"
    echo "Kong Admin URL: $KONG_ADMIN_URL"
    echo "Keycloak URL: $KEYCLOAK_URL"
    echo "Keycloak Realm: $KEYCLOAK_REALM"
    echo "JWT Issuer: ${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
    echo ""
    
    log_info "Available Routes:"
    curl -s "${KONG_ADMIN_URL}/routes" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for route in data['data']:
    methods = ', '.join(route.get('methods', []))
    paths = ', '.join(route.get('paths', []))
    print(f'  {route[\"name\"]}: {methods} {paths}')
" 2>/dev/null || log_warning "Could not fetch routes information"
    
    echo ""
    log_info "Available Consumers:"
    curl -s "${KONG_ADMIN_URL}/consumers" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for consumer in data['data']:
    print(f'  {consumer[\"username\"]}')
" 2>/dev/null || log_warning "Could not fetch consumers information"
    
    echo ""
    log_success "API Gateway setup completed successfully! 🎉"
    echo ""
    echo "🔗 Test the API Gateway:"
    echo "  Health Check: curl ${KONG_PROXY_URL}/actuator/health"
    echo "  Create Alert: curl -X POST ${KONG_PROXY_URL}/api/v1/alerts -H 'Authorization: Bearer <JWT_TOKEN>' -H 'Content-Type: application/json' -d '{...}'"
    echo ""
}

# Main execution
main() {
    log_info "Starting API Gateway setup..."
    
    # Wait for required services
    wait_for_service "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" "Keycloak" || exit 1
    wait_for_service "${KONG_ADMIN_URL}/status" "Kong" || exit 1
    
    # Configure Kong with Keycloak
    fetch_keycloak_public_key || exit 1
    configure_kong_jwt || exit 1
    configure_api_keys || exit 1
    
    # Verify configuration
    verify_kong_configuration || exit 1
    
    # Display summary
    display_summary
}

# Run main function
main "$@"