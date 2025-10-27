#!/bin/bash

# Complete API Gateway Deployment Script
# This script deploys Kong API Gateway with full security configuration

set -e

echo "🚀 Deploying Kong API Gateway for Eagle Alert System"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Step 1: Deploy Kong via Docker Compose
deploy_kong() {
    log_info "Deploying Kong API Gateway..."
    
    cd "$PROJECT_ROOT"
    
    # Start Kong and dependencies
    docker-compose up -d kong kong-database
    
    log_info "Waiting for Kong to be ready..."
    sleep 30
    
    # Check Kong status
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf http://localhost:8001/status > /dev/null 2>&1; then
            log_success "Kong is ready!"
            break
        fi
        
        log_info "Attempt $attempt/$max_attempts - Kong not ready yet..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Kong failed to start within expected time"
        return 1
    fi
}

# Step 2: Configure Keycloak Integration
configure_keycloak() {
    log_info "Configuring Keycloak integration..."
    
    # Make scripts executable
    chmod +x "$SCRIPT_DIR/setup-gateway.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/keycloak-integration.sh" 2>/dev/null || true
    
    # Run Keycloak integration
    if [ -f "$SCRIPT_DIR/setup-gateway.sh" ]; then
        "$SCRIPT_DIR/setup-gateway.sh"
    else
        log_warning "setup-gateway.sh not found, running basic configuration..."
        
        # Basic Keycloak integration
        local keycloak_url="http://localhost:8081"
        local realm="eagle-dev"
        
        # Wait for Keycloak
        log_info "Waiting for Keycloak..."
        local max_attempts=20
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if curl -sf "${keycloak_url}/realms/${realm}" > /dev/null 2>&1; then
                log_success "Keycloak is ready!"
                break
            fi
            sleep 5
            ((attempt++))
        done
        
        # Create basic consumers
        curl -X POST http://localhost:8001/consumers \
            -d "username=eagle-frontend" 2>/dev/null || true
        curl -X POST http://localhost:8001/consumers \
            -d "username=eagle-mobile" 2>/dev/null || true
        curl -X POST http://localhost:8001/consumers \
            -d "username=eagle-internal" 2>/dev/null || true
    fi
}

# Step 3: Validate Security Configuration
validate_security() {
    log_info "Validating security configuration..."
    
    # Make validation script executable
    chmod +x "$SCRIPT_DIR/validate-security.sh" 2>/dev/null || true
    
    if [ -f "$SCRIPT_DIR/validate-security.sh" ]; then
        "$SCRIPT_DIR/validate-security.sh"
    else
        log_warning "validate-security.sh not found, running basic validation..."
        
        # Basic validation
        local kong_status
        kong_status=$(curl -s http://localhost:8001/status | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print('OK' if data.get('database', {}).get('reachable') else 'ERROR')
except:
    print('ERROR')
" 2>/dev/null || echo "ERROR")
        
        if [ "$kong_status" = "OK" ]; then
            log_success "Kong basic validation passed"
        else
            log_error "Kong basic validation failed"
            return 1
        fi
    fi
}

# Step 4: Display Configuration Summary
display_summary() {
    log_info "API Gateway deployment summary..."
    
    echo ""
    echo "📋 Kong API Gateway Configuration"
    echo "================================"
    echo "Kong Admin API: http://localhost:8001"
    echo "Kong Proxy: http://localhost:8080"
    echo "Kong Proxy HTTPS: https://localhost:8443"
    echo ""
    
    # Display routes
    echo "🔗 Available Routes:"
    curl -s http://localhost:8001/routes 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for route in data.get('data', []):
        methods = ', '.join(route.get('methods', []))
        paths = ', '.join(route.get('paths', []))
        print(f'  {route.get(\"name\", \"unknown\")}: {methods} {paths}')
except:
    print('  Could not fetch routes')
" || echo "  Could not fetch routes"
    
    echo ""
    
    # Display consumers
    echo "👥 Configured Consumers:"
    curl -s http://localhost:8001/consumers 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for consumer in data.get('data', []):
        print(f'  {consumer.get(\"username\", \"unknown\")}')
except:
    print('  Could not fetch consumers')
" || echo "  Could not fetch consumers"
    
    echo ""
    
    # Display plugins
    echo "🔌 Active Plugins:"
    curl -s http://localhost:8001/plugins 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    plugins = {}
    for plugin in data.get('data', []):
        name = plugin.get('name', 'unknown')
        plugins[name] = plugins.get(name, 0) + 1
    
    for name, count in sorted(plugins.items()):
        print(f'  {name}: {count}')
except:
    print('  Could not fetch plugins')
" || echo "  Could not fetch plugins"
    
    echo ""
    log_success "Kong API Gateway deployed successfully! 🎉"
    echo ""
    echo "🧪 Test Commands:"
    echo "  Health Check: curl http://localhost:8080/actuator/health"
    echo "  Admin API: curl http://localhost:8001/status"
    echo ""
    echo "📚 Next Steps:"
    echo "  1. Configure frontend to use http://localhost:8080 as API base URL"
    echo "  2. Obtain JWT tokens from Keycloak for authentication"
    echo "  3. Monitor logs: docker-compose logs -f kong"
    echo "  4. View metrics: curl http://localhost:8080/metrics"
}

# Main deployment function
main() {
    log_info "Starting Kong API Gateway deployment..."
    
    # Check prerequisites
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose is required but not installed"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    # Run deployment steps
    deploy_kong || exit 1
    configure_keycloak || exit 1
    validate_security || log_warning "Security validation had issues"
    display_summary
    
    log_success "Kong API Gateway deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"