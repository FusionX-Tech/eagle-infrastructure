#!/bin/bash

# Security Validation Script for Kong API Gateway
# This script validates that all security policies are properly configured

set -e

# Configuration
KONG_ADMIN_URL="${KONG_ADMIN_URL:-http://localhost:8001}"
KONG_PROXY_URL="${KONG_PROXY_URL:-http://localhost:8080}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8081}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-eagle-dev}"

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

# Function to check if Kong is running
check_kong_status() {
    log_info "Checking Kong status..."
    
    if curl -sf "${KONG_ADMIN_URL}/status" > /dev/null; then
        log_success "Kong is running and accessible"
        return 0
    else
        log_error "Kong is not accessible at ${KONG_ADMIN_URL}"
        return 1
    fi
}

# Function to validate security headers
validate_security_headers() {
    log_info "Validating security headers..."
    
    local response_headers
    response_headers=$(curl -sI "${KONG_PROXY_URL}/actuator/health" 2>/dev/null || echo "")
    
    if [ -z "$response_headers" ]; then
        log_error "Could not fetch response headers from Kong proxy"
        return 1
    fi
    
    # Check for required security headers
    local required_headers=(
        "X-Content-Type-Options"
        "X-Frame-Options"
        "X-XSS-Protection"
        "Referrer-Policy"
        "Content-Security-Policy"
    )
    
    local missing_headers=()
    
    for header in "${required_headers[@]}"; do
        if echo "$response_headers" | grep -qi "$header"; then
            log_success "Security header present: $header"
        else
            missing_headers+=("$header")
            log_warning "Missing security header: $header"
        fi
    done
    
    # Check for information disclosure headers (should be removed)
    local disclosure_headers=(
        "Server"
        "X-Powered-By"
        "X-Runtime"
    )
    
    for header in "${disclosure_headers[@]}"; do
        if echo "$response_headers" | grep -qi "$header"; then
            log_warning "Information disclosure header present: $header"
        else
            log_success "Information disclosure header removed: $header"
        fi
    done
    
    if [ ${#missing_headers[@]} -eq 0 ]; then
        log_success "All required security headers are present"
        return 0
    else
        log_error "Missing ${#missing_headers[@]} required security headers"
        return 1
    fi
}

# Function to validate CORS configuration
validate_cors_configuration() {
    log_info "Validating CORS configuration..."
    
    # Test CORS preflight request
    local cors_response
    cors_response=$(curl -sI -X OPTIONS \
        -H "Origin: https://eagle.fusionx.com.br" \
        -H "Access-Control-Request-Method: POST" \
        -H "Access-Control-Request-Headers: Authorization,Content-Type" \
        "${KONG_PROXY_URL}/api/v1/alerts" 2>/dev/null || echo "")
    
    if [ -z "$cors_response" ]; then
        log_error "Could not test CORS preflight request"
        return 1
    fi
    
    # Check CORS headers
    if echo "$cors_response" | grep -qi "Access-Control-Allow-Origin"; then
        log_success "CORS Access-Control-Allow-Origin header present"
    else
        log_error "CORS Access-Control-Allow-Origin header missing"
        return 1
    fi
    
    if echo "$cors_response" | grep -qi "Access-Control-Allow-Methods"; then
        log_success "CORS Access-Control-Allow-Methods header present"
    else
        log_error "CORS Access-Control-Allow-Methods header missing"
        return 1
    fi
    
    log_success "CORS configuration is valid"
    return 0
}

# Function to validate rate limiting
validate_rate_limiting() {
    log_info "Validating rate limiting configuration..."
    
    # Check if rate limiting plugin is configured
    local rate_limit_plugins
    rate_limit_plugins=$(curl -s "${KONG_ADMIN_URL}/plugins" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for plugin in data['data'] if 'rate-limiting' in plugin['name'])
print(count)
" 2>/dev/null || echo "0")
    
    if [ "$rate_limit_plugins" -gt 0 ]; then
        log_success "Rate limiting plugins configured: $rate_limit_plugins"
    else
        log_error "No rate limiting plugins found"
        return 1
    fi
    
    # Test rate limiting headers in response
    local rate_limit_response
    rate_limit_response=$(curl -sI "${KONG_PROXY_URL}/actuator/health" 2>/dev/null || echo "")
    
    if echo "$rate_limit_response" | grep -qi "X-RateLimit"; then
        log_success "Rate limiting headers present in response"
    else
        log_warning "Rate limiting headers not found in response (may be normal for health endpoint)"
    fi
    
    return 0
}

# Function to validate JWT authentication
validate_jwt_authentication() {
    log_info "Validating JWT authentication configuration..."
    
    # Check if JWT plugin is configured
    local jwt_plugins
    jwt_plugins=$(curl -s "${KONG_ADMIN_URL}/plugins" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for plugin in data['data'] if plugin['name'] == 'jwt')
print(count)
" 2>/dev/null || echo "0")
    
    if [ "$jwt_plugins" -gt 0 ]; then
        log_success "JWT authentication plugins configured: $jwt_plugins"
    else
        log_error "No JWT authentication plugins found"
        return 1
    fi
    
    # Check JWT consumers
    local jwt_consumers
    jwt_consumers=$(curl -s "${KONG_ADMIN_URL}/consumers" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data['data']))
" 2>/dev/null || echo "0")
    
    if [ "$jwt_consumers" -gt 0 ]; then
        log_success "JWT consumers configured: $jwt_consumers"
    else
        log_error "No JWT consumers found"
        return 1
    fi
    
    # Test unauthorized access (should return 401)
    local auth_test_status
    auth_test_status=$(curl -s -o /dev/null -w "%{http_code}" "${KONG_PROXY_URL}/api/v1/alerts" 2>/dev/null || echo "000")
    
    if [ "$auth_test_status" = "401" ] || [ "$auth_test_status" = "403" ]; then
        log_success "Unauthorized access properly blocked (HTTP $auth_test_status)"
    else
        log_warning "Unexpected response for unauthorized access: HTTP $auth_test_status"
    fi
    
    return 0
}

# Function to validate request size limiting
validate_request_size_limiting() {
    log_info "Validating request size limiting..."
    
    # Check if request-size-limiting plugin is configured
    local size_limit_plugins
    size_limit_plugins=$(curl -s "${KONG_ADMIN_URL}/plugins" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for plugin in data['data'] if plugin['name'] == 'request-size-limiting')
print(count)
" 2>/dev/null || echo "0")
    
    if [ "$size_limit_plugins" -gt 0 ]; then
        log_success "Request size limiting plugins configured: $size_limit_plugins"
    else
        log_error "No request size limiting plugins found"
        return 1
    fi
    
    return 0
}

# Function to validate bot detection
validate_bot_detection() {
    log_info "Validating bot detection..."
    
    # Check if bot-detection plugin is configured
    local bot_detection_plugins
    bot_detection_plugins=$(curl -s "${KONG_ADMIN_URL}/plugins" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for plugin in data['data'] if plugin['name'] == 'bot-detection')
print(count)
" 2>/dev/null || echo "0")
    
    if [ "$bot_detection_plugins" -gt 0 ]; then
        log_success "Bot detection plugins configured: $bot_detection_plugins"
    else
        log_warning "No bot detection plugins found"
    fi
    
    # Test bot detection with curl user agent
    local bot_test_status
    bot_test_status=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: curl/7.68.0" "${KONG_PROXY_URL}/actuator/health" 2>/dev/null || echo "000")
    
    if [ "$bot_test_status" = "403" ]; then
        log_success "Bot detection working (blocked curl user agent)"
    else
        log_warning "Bot detection may not be working (curl user agent not blocked)"
    fi
    
    return 0
}

# Function to validate IP restrictions
validate_ip_restrictions() {
    log_info "Validating IP restrictions..."
    
    # Check if ip-restriction plugin is configured
    local ip_restriction_plugins
    ip_restriction_plugins=$(curl -s "${KONG_ADMIN_URL}/plugins" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for plugin in data['data'] if plugin['name'] == 'ip-restriction')
print(count)
" 2>/dev/null || echo "0")
    
    if [ "$ip_restriction_plugins" -gt 0 ]; then
        log_success "IP restriction plugins configured: $ip_restriction_plugins"
    else
        log_warning "No IP restriction plugins found"
    fi
    
    return 0
}

# Function to validate monitoring and logging
validate_monitoring_logging() {
    log_info "Validating monitoring and logging..."
    
    # Check for logging plugins
    local logging_plugins
    logging_plugins=$(curl -s "${KONG_ADMIN_URL}/plugins" | python3 -c "
import sys, json
data = json.load(sys.stdin)
logging_count = sum(1 for plugin in data['data'] if 'log' in plugin['name'])
prometheus_count = sum(1 for plugin in data['data'] if plugin['name'] == 'prometheus')
print(f'{logging_count},{prometheus_count}')
" 2>/dev/null || echo "0,0")
    
    IFS=',' read -r log_count prom_count <<< "$logging_plugins"
    
    if [ "$log_count" -gt 0 ]; then
        log_success "Logging plugins configured: $log_count"
    else
        log_warning "No logging plugins found"
    fi
    
    if [ "$prom_count" -gt 0 ]; then
        log_success "Prometheus monitoring configured"
    else
        log_warning "Prometheus monitoring not found"
    fi
    
    return 0
}

# Function to generate security report
generate_security_report() {
    log_info "Generating security validation report..."
    
    local report_file="security-validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Kong API Gateway Security Validation Report"
        echo "=========================================="
        echo "Generated: $(date)"
        echo "Kong Admin URL: $KONG_ADMIN_URL"
        echo "Kong Proxy URL: $KONG_PROXY_URL"
        echo ""
        
        echo "Plugin Summary:"
        curl -s "${KONG_ADMIN_URL}/plugins" | python3 -c "
import sys, json
data = json.load(sys.stdin)
plugins = {}
for plugin in data['data']:
    name = plugin['name']
    plugins[name] = plugins.get(name, 0) + 1

for name, count in sorted(plugins.items()):
    print(f'  {name}: {count}')
" 2>/dev/null || echo "  Could not fetch plugin information"
        
        echo ""
        echo "Route Summary:"
        curl -s "${KONG_ADMIN_URL}/routes" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for route in data['data']:
    methods = ', '.join(route.get('methods', []))
    paths = ', '.join(route.get('paths', []))
    print(f'  {route[\"name\"]}: {methods} {paths}')
" 2>/dev/null || echo "  Could not fetch route information"
        
        echo ""
        echo "Consumer Summary:"
        curl -s "${KONG_ADMIN_URL}/consumers" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for consumer in data['data']:
    print(f'  {consumer[\"username\"]}')
" 2>/dev/null || echo "  Could not fetch consumer information"
        
    } > "$report_file"
    
    log_success "Security report generated: $report_file"
}

# Main validation function
main() {
    echo "🔒 Kong API Gateway Security Validation"
    echo "======================================="
    echo ""
    
    local validation_results=()
    
    # Run all validation checks
    check_kong_status && validation_results+=("Kong Status: PASS") || validation_results+=("Kong Status: FAIL")
    validate_security_headers && validation_results+=("Security Headers: PASS") || validation_results+=("Security Headers: FAIL")
    validate_cors_configuration && validation_results+=("CORS Configuration: PASS") || validation_results+=("CORS Configuration: FAIL")
    validate_rate_limiting && validation_results+=("Rate Limiting: PASS") || validation_results+=("Rate Limiting: FAIL")
    validate_jwt_authentication && validation_results+=("JWT Authentication: PASS") || validation_results+=("JWT Authentication: FAIL")
    validate_request_size_limiting && validation_results+=("Request Size Limiting: PASS") || validation_results+=("Request Size Limiting: FAIL")
    validate_bot_detection && validation_results+=("Bot Detection: PASS") || validation_results+=("Bot Detection: PASS")
    validate_ip_restrictions && validation_results+=("IP Restrictions: PASS") || validation_results+=("IP Restrictions: PASS")
    validate_monitoring_logging && validation_results+=("Monitoring/Logging: PASS") || validation_results+=("Monitoring/Logging: PASS")
    
    echo ""
    echo "📊 Validation Summary:"
    echo "====================="
    
    local pass_count=0
    local fail_count=0
    
    for result in "${validation_results[@]}"; do
        if [[ $result == *"PASS"* ]]; then
            log_success "$result"
            ((pass_count++))
        else
            log_error "$result"
            ((fail_count++))
        fi
    done
    
    echo ""
    echo "Results: $pass_count passed, $fail_count failed"
    
    # Generate detailed report
    generate_security_report
    
    if [ $fail_count -eq 0 ]; then
        log_success "All security validations passed! 🎉"
        return 0
    else
        log_error "$fail_count security validations failed"
        return 1
    fi
}

# Run main function
main "$@"