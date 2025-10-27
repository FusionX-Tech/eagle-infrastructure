#!/bin/bash

# Keycloak Configuration Validation Script
# This script validates the Keycloak realm and service accounts configuration

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYCLOAK_DIR="$(dirname "$SCRIPT_DIR")"
IMPORT_DIR="$KEYCLOAK_DIR/import"

# Default values
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM_NAME="${REALM_NAME:-eagle-dev}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Function to increment error count
increment_errors() {
    ((VALIDATION_ERRORS++))
}

# Function to increment warning count
increment_warnings() {
    ((VALIDATION_WARNINGS++))
}

# Function to validate Keycloak connectivity
validate_keycloak_connectivity() {
    log_info "Validating Keycloak connectivity..."
    
    # Test health endpoint
    if curl -s -f "$KEYCLOAK_URL/health/ready" > /dev/null 2>&1; then
        log_success "Keycloak health endpoint is accessible"
    else
        log_error "Keycloak health endpoint is not accessible"
        increment_errors
        return 1
    fi
    
    # Test realm endpoint
    if curl -s -f "$KEYCLOAK_URL/realms/$REALM_NAME" > /dev/null 2>&1; then
        log_success "Realm $REALM_NAME is accessible"
    else
        log_error "Realm $REALM_NAME is not accessible"
        increment_errors
        return 1
    fi
    
    # Test JWKS endpoint
    if curl -s -f "$KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/certs" > /dev/null 2>&1; then
        log_success "JWKS endpoint is accessible"
    else
        log_error "JWKS endpoint is not accessible"
        increment_errors
    fi
    
    # Test token endpoint
    if curl -s -f "$KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/token" > /dev/null 2>&1; then
        log_success "Token endpoint is accessible"
    else
        log_error "Token endpoint is not accessible"
        increment_errors
    fi
}

# Function to validate realm configuration
validate_realm_configuration() {
    log_info "Validating realm configuration..."
    
    # Get realm configuration
    local realm_info=$(curl -s "$KEYCLOAK_URL/realms/$REALM_NAME")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to retrieve realm information"
        increment_errors
        return 1
    fi
    
    # Check realm name
    local realm_name=$(echo "$realm_info" | jq -r '.realm')
    if [ "$realm_name" = "$REALM_NAME" ]; then
        log_success "Realm name is correct: $realm_name"
    else
        log_error "Realm name mismatch. Expected: $REALM_NAME, Got: $realm_name"
        increment_errors
    fi
    
    # Check if realm is enabled
    local realm_enabled=$(echo "$realm_info" | jq -r '.enabled // false')
    if [ "$realm_enabled" = "true" ]; then
        log_success "Realm is enabled"
    else
        log_error "Realm is not enabled"
        increment_errors
    fi
    
    # Check token lifespan
    local token_lifespan=$(echo "$realm_info" | jq -r '.accessTokenLifespan // 0')
    if [ "$token_lifespan" -gt 0 ] && [ "$token_lifespan" -le 600 ]; then
        log_success "Access token lifespan is configured: ${token_lifespan}s"
    else
        log_warning "Access token lifespan might be too long: ${token_lifespan}s"
        increment_warnings
    fi
}

# Function to validate service accounts
validate_service_accounts() {
    log_info "Validating service accounts..."
    
    if [ ! -f "$IMPORT_DIR/service-accounts-config.json" ]; then
        log_error "Service accounts configuration file not found"
        increment_errors
        return 1
    fi
    
    # Read service accounts configuration
    local service_accounts=$(jq -c '.serviceAccounts[]' "$IMPORT_DIR/service-accounts-config.json")
    
    while IFS= read -r account; do
        local client_id=$(echo "$account" | jq -r '.clientId')
        local client_secret=$(echo "$account" | jq -r '.clientSecret')
        local expected_roles=$(echo "$account" | jq -r '.assignedRoles[]')
        
        log_info "Validating service account: $client_id"
        
        # Test token generation
        local token_response=$(curl -s -X POST "$KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials" \
            -d "client_id=$client_id" \
            -d "client_secret=$client_secret" \
            -d "scope=microservice-communication" 2>/dev/null)
        
        if echo "$token_response" | jq -e '.access_token' > /dev/null 2>&1; then
            log_success "Token generation successful for $client_id"
            
            # Validate token content
            local access_token=$(echo "$token_response" | jq -r '.access_token')
            local token_payload=$(echo "$access_token" | cut -d'.' -f2)
            
            # Add padding if needed for base64 decoding
            local padding=$((4 - ${#token_payload} % 4))
            if [ $padding -ne 4 ]; then
                token_payload="${token_payload}$(printf '%*s' $padding | tr ' ' '=')"
            fi
            
            local decoded_payload=$(echo "$token_payload" | base64 -d 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                # Check token expiration
                local exp=$(echo "$decoded_payload" | jq -r '.exp // 0')
                local iat=$(echo "$decoded_payload" | jq -r '.iat // 0')
                local token_lifetime=$((exp - iat))
                
                if [ "$token_lifetime" -gt 0 ] && [ "$token_lifetime" -le 600 ]; then
                    log_success "Token lifetime is appropriate: ${token_lifetime}s"
                else
                    log_warning "Token lifetime might be inappropriate: ${token_lifetime}s"
                    increment_warnings
                fi
                
                # Check issuer
                local issuer=$(echo "$decoded_payload" | jq -r '.iss // ""')
                local expected_issuer="$KEYCLOAK_URL/realms/$REALM_NAME"
                if [ "$issuer" = "$expected_issuer" ]; then
                    log_success "Token issuer is correct"
                else
                    log_error "Token issuer mismatch. Expected: $expected_issuer, Got: $issuer"
                    increment_errors
                fi
                
                # Check audience
                local audience=$(echo "$decoded_payload" | jq -r '.aud // ""')
                if [ -n "$audience" ]; then
                    log_success "Token audience is present: $audience"
                else
                    log_warning "Token audience is not set"
                    increment_warnings
                fi
                
                # Check roles
                local token_roles=$(echo "$decoded_payload" | jq -r '.realm_access.roles[]?' 2>/dev/null | sort)
                if [ -n "$token_roles" ]; then
                    log_success "Token contains roles: $(echo "$token_roles" | tr '\n' ',' | sed 's/,$//')"
                    
                    # Validate expected roles are present
                    while IFS= read -r expected_role; do
                        if echo "$token_roles" | grep -q "^$expected_role$"; then
                            log_success "Expected role '$expected_role' is present"
                        else
                            log_warning "Expected role '$expected_role' is missing"
                            increment_warnings
                        fi
                    done <<< "$expected_roles"
                else
                    log_warning "Token does not contain realm roles"
                    increment_warnings
                fi
            else
                log_warning "Could not decode token payload for validation"
                increment_warnings
            fi
        else
            log_error "Token generation failed for $client_id"
            log_error "Response: $token_response"
            increment_errors
        fi
        
    done <<< "$service_accounts"
}

# Function to validate security configuration
validate_security_configuration() {
    log_info "Validating security configuration..."
    
    # Get realm configuration for security settings
    local realm_info=$(curl -s "$KEYCLOAK_URL/realms/$REALM_NAME")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to retrieve realm information for security validation"
        increment_errors
        return 1
    fi
    
    # Check SSL requirement
    local ssl_required=$(echo "$realm_info" | jq -r '.sslRequired // "none"')
    if [ "$ssl_required" != "none" ]; then
        log_success "SSL is required: $ssl_required"
    else
        log_warning "SSL is not required - this might be acceptable for development"
        increment_warnings
    fi
    
    # Validate JWKS keys
    local jwks_response=$(curl -s "$KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/certs")
    local key_count=$(echo "$jwks_response" | jq '.keys | length')
    
    if [ "$key_count" -gt 0 ]; then
        log_success "JWKS contains $key_count key(s)"
        
        # Check key algorithms
        local algorithms=$(echo "$jwks_response" | jq -r '.keys[].alg' | sort -u)
        log_info "Available key algorithms: $(echo "$algorithms" | tr '\n' ',' | sed 's/,$//')"
        
        if echo "$algorithms" | grep -q "RS256"; then
            log_success "RS256 algorithm is available"
        else
            log_warning "RS256 algorithm is not available"
            increment_warnings
        fi
    else
        log_error "No keys found in JWKS"
        increment_errors
    fi
}

# Function to validate environment-specific configuration
validate_environment_configuration() {
    log_info "Validating environment-specific configuration..."
    
    local env_file="$IMPORT_DIR/environments/${ENVIRONMENT}.env"
    
    if [ -f "$env_file" ]; then
        log_success "Environment configuration file exists: $env_file"
        
        # Source the environment file and validate key variables
        source "$env_file"
        
        # Validate required environment variables
        local required_vars=("KEYCLOAK_REALM" "KEYCLOAK_ISSUER_URI" "MS_CUSTOMER_CLIENT_ID")
        
        for var in "${required_vars[@]}"; do
            if [ -n "${!var}" ]; then
                log_success "Environment variable $var is set"
            else
                log_error "Environment variable $var is not set"
                increment_errors
            fi
        done
        
        # Validate token lifespans for environment
        if [ "$ENVIRONMENT" = "prod" ]; then
            if [ "${ACCESS_TOKEN_LIFESPAN:-300}" -le 300 ]; then
                log_success "Production token lifespan is appropriately short"
            else
                log_warning "Production token lifespan might be too long"
                increment_warnings
            fi
        fi
    else
        log_warning "Environment configuration file not found: $env_file"
        increment_warnings
    fi
}

# Function to generate validation report
generate_validation_report() {
    log_info "Generating validation report..."
    
    local report_file="$KEYCLOAK_DIR/validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
Keycloak Configuration Validation Report
========================================

Date: $(date)
Environment: $ENVIRONMENT
Keycloak URL: $KEYCLOAK_URL
Realm: $REALM_NAME

Summary:
--------
Validation Errors: $VALIDATION_ERRORS
Validation Warnings: $VALIDATION_WARNINGS

Status: $([ $VALIDATION_ERRORS -eq 0 ] && echo "PASSED" || echo "FAILED")

Details:
--------
EOF
    
    # Add detailed results to report
    echo "See console output for detailed validation results" >> "$report_file"
    
    log_info "Validation report saved to: $report_file"
}

# Main execution
main() {
    log_info "Starting Keycloak configuration validation..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Keycloak URL: $KEYCLOAK_URL"
    log_info "Realm: $REALM_NAME"
    
    echo "========================================"
    
    # Run validations
    validate_keycloak_connectivity
    validate_realm_configuration
    validate_service_accounts
    validate_security_configuration
    validate_environment_configuration
    
    echo "========================================"
    
    # Generate report
    generate_validation_report
    
    # Final summary
    log_info "Validation completed"
    log_info "Errors: $VALIDATION_ERRORS"
    log_info "Warnings: $VALIDATION_WARNINGS"
    
    if [ $VALIDATION_ERRORS -eq 0 ]; then
        log_success "All validations passed!"
        if [ $VALIDATION_WARNINGS -gt 0 ]; then
            log_warning "There are $VALIDATION_WARNINGS warning(s) that should be reviewed"
        fi
        exit 0
    else
        log_error "Validation failed with $VALIDATION_ERRORS error(s)"
        exit 1
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -u, --url URL           Keycloak URL (default: http://localhost:8080)"
    echo "  -r, --realm REALM       Realm name (default: eagle-dev)"
    echo "  -e, --environment ENV   Environment (dev/prod) (default: dev)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  KEYCLOAK_URL            Keycloak URL"
    echo "  REALM_NAME              Realm name"
    echo "  ENVIRONMENT             Environment"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            KEYCLOAK_URL="$2"
            shift 2
            ;;
        -r|--realm)
            REALM_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check dependencies
if ! command -v curl &> /dev/null; then
    log_error "curl is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    exit 1
fi

# Run main function
main