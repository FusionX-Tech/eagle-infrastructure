#!/bin/bash

# Keycloak Setup Automation Script
# This script automates the setup of Keycloak realm and service accounts

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYCLOAK_DIR="$(dirname "$SCRIPT_DIR")"
IMPORT_DIR="$KEYCLOAK_DIR/import"

# Default values
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin123}"
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

# Function to check if Keycloak is running
check_keycloak_health() {
    log_info "Checking Keycloak health..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$KEYCLOAK_URL/health/ready" > /dev/null 2>&1; then
            log_success "Keycloak is ready"
            return 0
        fi
        
        log_info "Waiting for Keycloak to be ready (attempt $attempt/$max_attempts)..."
        sleep 5
        ((attempt++))
    done
    
    log_error "Keycloak is not ready after $max_attempts attempts"
    return 1
}

# Function to get admin access token
get_admin_token() {
    log_info "Getting admin access token..."
    
    local response=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$KEYCLOAK_ADMIN_USER" \
        -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to get admin token"
        return 1
    fi
    
    echo "$response" | jq -r '.access_token'
}

# Function to check if realm exists
realm_exists() {
    local token="$1"
    local realm="$2"
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "$KEYCLOAK_URL/admin/realms/$realm")
    
    [ "$response" = "200" ]
}

# Function to import realm
import_realm() {
    local token="$1"
    local realm_file="$2"
    
    log_info "Importing realm from $realm_file..."
    
    local response=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "@$realm_file")
    
    if [ $? -eq 0 ]; then
        log_success "Realm imported successfully"
        return 0
    else
        log_error "Failed to import realm: $response"
        return 1
    fi
}

# Function to update realm
update_realm() {
    local token="$1"
    local realm="$2"
    local realm_file="$3"
    
    log_info "Updating realm $realm..."
    
    local response=$(curl -s -X PUT "$KEYCLOAK_URL/admin/realms/$realm" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "@$realm_file")
    
    if [ $? -eq 0 ]; then
        log_success "Realm updated successfully"
        return 0
    else
        log_error "Failed to update realm: $response"
        return 1
    fi
}

# Function to validate service accounts
validate_service_accounts() {
    local token="$1"
    local realm="$2"
    
    log_info "Validating service accounts..."
    
    # Read service accounts configuration
    local service_accounts=$(jq -r '.serviceAccounts[].clientId' "$IMPORT_DIR/service-accounts-config.json")
    
    for client_id in $service_accounts; do
        log_info "Validating service account: $client_id"
        
        # Check if client exists
        local client_response=$(curl -s \
            -H "Authorization: Bearer $token" \
            "$KEYCLOAK_URL/admin/realms/$realm/clients?clientId=$client_id")
        
        local client_count=$(echo "$client_response" | jq '. | length')
        
        if [ "$client_count" -eq 1 ]; then
            log_success "Service account $client_id exists"
            
            # Get client UUID
            local client_uuid=$(echo "$client_response" | jq -r '.[0].id')
            
            # Check service account user
            local service_account_response=$(curl -s \
                -H "Authorization: Bearer $token" \
                "$KEYCLOAK_URL/admin/realms/$realm/clients/$client_uuid/service-account-user")
            
            if [ $? -eq 0 ]; then
                local username=$(echo "$service_account_response" | jq -r '.username')
                log_success "Service account user exists: $username"
            else
                log_error "Service account user not found for $client_id"
            fi
        else
            log_error "Service account $client_id not found or duplicated"
        fi
    done
}

# Function to test token generation
test_token_generation() {
    local realm="$2"
    
    log_info "Testing token generation for service accounts..."
    
    # Read service accounts configuration
    local service_accounts=$(jq -c '.serviceAccounts[]' "$IMPORT_DIR/service-accounts-config.json")
    
    while IFS= read -r account; do
        local client_id=$(echo "$account" | jq -r '.clientId')
        local client_secret=$(echo "$account" | jq -r '.clientSecret')
        
        log_info "Testing token generation for $client_id..."
        
        local token_response=$(curl -s -X POST "$KEYCLOAK_URL/realms/$realm/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=client_credentials" \
            -d "client_id=$client_id" \
            -d "client_secret=$client_secret" \
            -d "scope=microservice-communication")
        
        if echo "$token_response" | jq -e '.access_token' > /dev/null 2>&1; then
            log_success "Token generation successful for $client_id"
            
            # Decode and display token info
            local access_token=$(echo "$token_response" | jq -r '.access_token')
            local token_payload=$(echo "$access_token" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.')
            
            if [ $? -eq 0 ]; then
                local roles=$(echo "$token_payload" | jq -r '.realm_access.roles[]?' | tr '\n' ',' | sed 's/,$//')
                log_info "Assigned roles for $client_id: $roles"
            fi
        else
            log_error "Token generation failed for $client_id: $token_response"
        fi
    done <<< "$service_accounts"
}

# Main execution
main() {
    log_info "Starting Keycloak setup automation..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Keycloak URL: $KEYCLOAK_URL"
    log_info "Realm: $REALM_NAME"
    
    # Check if required files exist
    if [ ! -f "$IMPORT_DIR/eagle-realm.json" ]; then
        log_error "Realm configuration file not found: $IMPORT_DIR/eagle-realm.json"
        exit 1
    fi
    
    if [ ! -f "$IMPORT_DIR/service-accounts-config.json" ]; then
        log_error "Service accounts configuration file not found: $IMPORT_DIR/service-accounts-config.json"
        exit 1
    fi
    
    # Check Keycloak health
    if ! check_keycloak_health; then
        exit 1
    fi
    
    # Get admin token
    local admin_token=$(get_admin_token)
    if [ -z "$admin_token" ] || [ "$admin_token" = "null" ]; then
        log_error "Failed to get admin token"
        exit 1
    fi
    
    log_success "Admin token obtained"
    
    # Check if realm exists and import/update accordingly
    if realm_exists "$admin_token" "$REALM_NAME"; then
        log_warning "Realm $REALM_NAME already exists"
        read -p "Do you want to update the existing realm? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_realm "$admin_token" "$REALM_NAME" "$IMPORT_DIR/eagle-realm.json"
        else
            log_info "Skipping realm update"
        fi
    else
        import_realm "$admin_token" "$IMPORT_DIR/eagle-realm.json"
    fi
    
    # Wait a bit for realm to be fully initialized
    sleep 5
    
    # Validate service accounts
    validate_service_accounts "$admin_token" "$REALM_NAME"
    
    # Test token generation
    test_token_generation "$admin_token" "$REALM_NAME"
    
    log_success "Keycloak setup completed successfully!"
    log_info "You can now configure your microservices to use the following endpoints:"
    log_info "  Token endpoint: $KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/token"
    log_info "  JWKS endpoint: $KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/certs"
    log_info "  Issuer URI: $KEYCLOAK_URL/realms/$REALM_NAME"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -u, --url URL           Keycloak URL (default: http://localhost:8080)"
    echo "  -a, --admin USER        Admin username (default: admin)"
    echo "  -p, --password PASS     Admin password (default: admin123)"
    echo "  -r, --realm REALM       Realm name (default: eagle-dev)"
    echo "  -e, --environment ENV   Environment (dev/prod) (default: dev)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  KEYCLOAK_URL            Keycloak URL"
    echo "  KEYCLOAK_ADMIN_USER     Admin username"
    echo "  KEYCLOAK_ADMIN_PASSWORD Admin password"
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
        -a|--admin)
            KEYCLOAK_ADMIN_USER="$2"
            shift 2
            ;;
        -p|--password)
            KEYCLOAK_ADMIN_PASSWORD="$2"
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