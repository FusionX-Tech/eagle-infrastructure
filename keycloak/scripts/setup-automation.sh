#!/bin/bash

# Keycloak Setup Automation Orchestrator
# This script orchestrates the complete Keycloak setup and configuration process

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
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
BACKUP_BEFORE_SETUP="${BACKUP_BEFORE_SETUP:-true}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check required commands
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install the missing dependencies and try again"
        return 1
    fi
    
    # Check required files
    local required_files=(
        "$IMPORT_DIR/eagle-realm.json"
        "$IMPORT_DIR/service-accounts-config.json"
        "$IMPORT_DIR/environments/${ENVIRONMENT}.env"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file not found: $file"
            return 1
        fi
    done
    
    log_success "All prerequisites satisfied"
    return 0
}

# Function to display configuration summary
display_configuration() {
    log_step "Configuration Summary"
    echo "========================================"
    echo "Environment: $ENVIRONMENT"
    echo "Keycloak URL: $KEYCLOAK_URL"
    echo "Realm Name: $REALM_NAME"
    echo "Admin User: $KEYCLOAK_ADMIN_USER"
    echo "Skip Validation: $SKIP_VALIDATION"
    echo "Backup Before Setup: $BACKUP_BEFORE_SETUP"
    echo "Auto Approve: $AUTO_APPROVE"
    echo "========================================"
}

# Function to wait for user confirmation
wait_for_confirmation() {
    if [ "$AUTO_APPROVE" = "true" ]; then
        return 0
    fi
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
}

# Function to check Keycloak health
check_keycloak_health() {
    log_step "Checking Keycloak health..."
    
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

# Function to backup existing configuration
backup_configuration() {
    if [ "$BACKUP_BEFORE_SETUP" = "true" ]; then
        log_step "Creating configuration backup..."
        
        if [ -f "$SCRIPT_DIR/keycloak-admin-api.sh" ]; then
            source "$SCRIPT_DIR/keycloak-admin-api.sh"
            backup_configuration
        else
            log_warning "Backup script not found, skipping backup"
        fi
    else
        log_info "Skipping configuration backup"
    fi
}

# Function to setup realm configuration
setup_realm() {
    log_step "Setting up realm configuration..."
    
    if [ -f "$SCRIPT_DIR/keycloak-admin-api.sh" ]; then
        source "$SCRIPT_DIR/keycloak-admin-api.sh"
        setup_realm_configuration
    else
        log_error "Admin API script not found: $SCRIPT_DIR/keycloak-admin-api.sh"
        return 1
    fi
}

# Function to validate configuration
validate_configuration() {
    if [ "$SKIP_VALIDATION" = "true" ]; then
        log_info "Skipping configuration validation"
        return 0
    fi
    
    log_step "Validating configuration..."
    
    if [ -f "$SCRIPT_DIR/validate-keycloak.sh" ]; then
        bash "$SCRIPT_DIR/validate-keycloak.sh" -u "$KEYCLOAK_URL" -r "$REALM_NAME" -e "$ENVIRONMENT"
    else
        log_warning "Validation script not found, skipping validation"
    fi
}

# Function to generate setup report
generate_setup_report() {
    log_step "Generating setup report..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local report_file="$KEYCLOAK_DIR/setup-report-$timestamp.txt"
    
    cat > "$report_file" << EOF
Keycloak Setup Automation Report
================================

Date: $(date)
Environment: $ENVIRONMENT
Keycloak URL: $KEYCLOAK_URL
Realm: $REALM_NAME

Configuration:
--------------
Admin User: $KEYCLOAK_ADMIN_USER
Skip Validation: $SKIP_VALIDATION
Backup Before Setup: $BACKUP_BEFORE_SETUP
Auto Approve: $AUTO_APPROVE

Setup Steps Completed:
----------------------
1. Prerequisites Check: ✓
2. Keycloak Health Check: ✓
3. Configuration Backup: $([ "$BACKUP_BEFORE_SETUP" = "true" ] && echo "✓" || echo "Skipped")
4. Realm Setup: ✓
5. Configuration Validation: $([ "$SKIP_VALIDATION" = "true" ] && echo "Skipped" || echo "✓")

Service Accounts Configured:
----------------------------
EOF
    
    # Add service accounts information
    if [ -f "$IMPORT_DIR/service-accounts-config.json" ]; then
        jq -r '.serviceAccounts[] | "- \(.clientId) (\(.clientName))"' "$IMPORT_DIR/service-accounts-config.json" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

Endpoints:
----------
Token Endpoint: $KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/token
JWKS Endpoint: $KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/certs
Issuer URI: $KEYCLOAK_URL/realms/$REALM_NAME

Next Steps:
-----------
1. Update microservice configurations with the new endpoints
2. Test service-to-service authentication
3. Monitor logs for any authentication issues
4. Consider setting up monitoring and alerting for Keycloak

EOF
    
    log_success "Setup report saved to: $report_file"
}

# Function to display next steps
display_next_steps() {
    log_step "Next Steps"
    echo "========================================"
    echo "1. Update microservice configurations:"
    echo "   - Set KEYCLOAK_ISSUER_URI=$KEYCLOAK_URL/realms/$REALM_NAME"
    echo "   - Configure client credentials for each service"
    echo ""
    echo "2. Test service-to-service authentication:"
    echo "   - Verify token generation for each service account"
    echo "   - Test API calls between microservices"
    echo ""
    echo "3. Monitor and maintain:"
    echo "   - Check Keycloak logs regularly"
    echo "   - Monitor token generation metrics"
    echo "   - Keep service account credentials secure"
    echo ""
    echo "4. Environment-specific configurations:"
    echo "   - Review $IMPORT_DIR/environments/${ENVIRONMENT}.env"
    echo "   - Adjust token lifespans as needed"
    echo "   - Configure SSL/TLS for production"
    echo "========================================"
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Setup failed with exit code $exit_code"
        log_info "Check the logs above for error details"
        log_info "You can re-run the script after fixing the issues"
    fi
}

# Main execution function
main() {
    log_info "Starting Keycloak Setup Automation"
    log_info "Script: $(basename "$0")"
    log_info "Version: 1.0.0"
    echo ""
    
    # Display configuration
    display_configuration
    
    # Wait for user confirmation
    wait_for_confirmation
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Check Keycloak health
    if ! check_keycloak_health; then
        exit 1
    fi
    
    # Backup existing configuration
    backup_configuration
    
    # Setup realm configuration
    if ! setup_realm; then
        log_error "Realm setup failed"
        exit 1
    fi
    
    # Validate configuration
    validate_configuration
    
    # Generate setup report
    generate_setup_report
    
    # Display next steps
    display_next_steps
    
    log_success "Keycloak setup automation completed successfully!"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --url URL               Keycloak URL (default: http://localhost:8080)"
    echo "  -a, --admin USER            Admin username (default: admin)"
    echo "  -p, --password PASS         Admin password (default: admin123)"
    echo "  -r, --realm REALM           Realm name (default: eagle-dev)"
    echo "  -e, --environment ENV       Environment (dev/prod) (default: dev)"
    echo "  --skip-validation           Skip configuration validation"
    echo "  --no-backup                 Skip configuration backup"
    echo "  --auto-approve              Auto approve all prompts"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  KEYCLOAK_URL                Keycloak URL"
    echo "  KEYCLOAK_ADMIN_USER         Admin username"
    echo "  KEYCLOAK_ADMIN_PASSWORD     Admin password"
    echo "  REALM_NAME                  Realm name"
    echo "  ENVIRONMENT                 Environment"
    echo "  SKIP_VALIDATION             Skip validation (true/false)"
    echo "  BACKUP_BEFORE_SETUP         Backup before setup (true/false)"
    echo "  AUTO_APPROVE                Auto approve prompts (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use defaults"
    echo "  $0 --environment prod --auto-approve # Production setup"
    echo "  $0 --skip-validation --no-backup     # Quick setup"
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
        --skip-validation)
            SKIP_VALIDATION="true"
            shift
            ;;
        --no-backup)
            BACKUP_BEFORE_SETUP="false"
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE="true"
            shift
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

# Set up cleanup trap
trap cleanup EXIT

# Run main function
main