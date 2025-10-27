#!/bin/bash

# Keycloak Admin API Automation Script
# This script provides functions to interact with Keycloak Admin API for automated configuration

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

# Global variables for API interaction
ADMIN_TOKEN=""
API_BASE_URL=""

# Function to initialize API connection
init_api_connection() {
    log_info "Initializing Keycloak Admin API connection..."
    
    API_BASE_URL="$KEYCLOAK_URL/admin/realms"
    
    # Get admin token
    ADMIN_TOKEN=$(get_admin_token)
    if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
        log_error "Failed to get admin token"
        return 1
    fi
    
    log_success "Admin API connection initialized"
    return 0
}

# Function to get admin access token
get_admin_token() {
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

# Function to make authenticated API request
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local content_type="${4:-application/json}"
    
    local curl_args=(-s -X "$method" -H "Authorization: Bearer $ADMIN_TOKEN")
    
    if [ -n "$data" ]; then
        curl_args+=(-H "Content-Type: $content_type" -d "$data")
    fi
    
    curl "${curl_args[@]}" "$API_BASE_URL/$endpoint"
}

# Function to create or update realm
create_or_update_realm() {
    local realm_config_file="$1"
    
    log_info "Creating or updating realm from $realm_config_file..."
    
    if [ ! -f "$realm_config_file" ]; then
        log_error "Realm configuration file not found: $realm_config_file"
        return 1
    fi
    
    # Check if realm exists
    local realm_response=$(api_request "GET" "$REALM_NAME")
    local http_code=$(echo "$realm_response" | jq -r '.error // "success"')
    
    if [ "$http_code" = "success" ]; then
        log_info "Realm $REALM_NAME exists, updating..."
        
        # Update realm
        local update_response=$(api_request "PUT" "$REALM_NAME" "@$realm_config_file")
        if [ $? -eq 0 ]; then
            log_success "Realm updated successfully"
        else
            log_error "Failed to update realm: $update_response"
            return 1
        fi
    else
        log_info "Realm $REALM_NAME does not exist, creating..."
        
        # Create realm
        local create_response=$(api_request "POST" "" "@$realm_config_file")
        if [ $? -eq 0 ]; then
            log_success "Realm created successfully"
        else
            log_error "Failed to create realm: $create_response"
            return 1
        fi
    fi
}

# Function to create or update client
create_or_update_client() {
    local client_config="$1"
    
    local client_id=$(echo "$client_config" | jq -r '.clientId')
    log_info "Creating or updating client: $client_id"
    
    # Check if client exists
    local existing_clients=$(api_request "GET" "$REALM_NAME/clients?clientId=$client_id")
    local client_count=$(echo "$existing_clients" | jq '. | length')
    
    if [ "$client_count" -eq 1 ]; then
        log_info "Client $client_id exists, updating..."
        
        # Get client UUID
        local client_uuid=$(echo "$existing_clients" | jq -r '.[0].id')
        
        # Update client
        local update_response=$(api_request "PUT" "$REALM_NAME/clients/$client_uuid" "$client_config")
        if [ $? -eq 0 ]; then
            log_success "Client $client_id updated successfully"
        else
            log_error "Failed to update client $client_id: $update_response"
            return 1
        fi
    else
        log_info "Client $client_id does not exist, creating..."
        
        # Create client
        local create_response=$(api_request "POST" "$REALM_NAME/clients" "$client_config")
        if [ $? -eq 0 ]; then
            log_success "Client $client_id created successfully"
        else
            log_error "Failed to create client $client_id: $create_response"
            return 1
        fi
    fi
}

# Function to create or update realm role
create_or_update_realm_role() {
    local role_config="$1"
    
    local role_name=$(echo "$role_config" | jq -r '.name')
    log_info "Creating or updating realm role: $role_name"
    
    # Check if role exists
    local existing_role=$(api_request "GET" "$REALM_NAME/roles/$role_name")
    local role_exists=$(echo "$existing_role" | jq -r '.name // "not_found"')
    
    if [ "$role_exists" = "$role_name" ]; then
        log_info "Role $role_name exists, updating..."
        
        # Update role
        local update_response=$(api_request "PUT" "$REALM_NAME/roles/$role_name" "$role_config")
        if [ $? -eq 0 ]; then
            log_success "Role $role_name updated successfully"
        else
            log_error "Failed to update role $role_name: $update_response"
            return 1
        fi
    else
        log_info "Role $role_name does not exist, creating..."
        
        # Create role
        local create_response=$(api_request "POST" "$REALM_NAME/roles" "$role_config")
        if [ $? -eq 0 ]; then
            log_success "Role $role_name created successfully"
        else
            log_error "Failed to create role $role_name: $create_response"
            return 1
        fi
    fi
}

# Function to assign roles to service account
assign_roles_to_service_account() {
    local client_id="$1"
    local roles_array="$2"
    
    log_info "Assigning roles to service account: $client_id"
    
    # Get client UUID
    local client_response=$(api_request "GET" "$REALM_NAME/clients?clientId=$client_id")
    local client_uuid=$(echo "$client_response" | jq -r '.[0].id')
    
    if [ -z "$client_uuid" ] || [ "$client_uuid" = "null" ]; then
        log_error "Client $client_id not found"
        return 1
    fi
    
    # Get service account user
    local service_account_user=$(api_request "GET" "$REALM_NAME/clients/$client_uuid/service-account-user")
    local user_id=$(echo "$service_account_user" | jq -r '.id')
    
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        log_error "Service account user not found for client $client_id"
        return 1
    fi
    
    # Get available realm roles
    local available_roles=$(api_request "GET" "$REALM_NAME/users/$user_id/role-mappings/realm/available")
    
    # Build role assignment payload
    local roles_to_assign="[]"
    
    while IFS= read -r role_name; do
        if [ -n "$role_name" ] && [ "$role_name" != "null" ]; then
            # Find role in available roles
            local role_obj=$(echo "$available_roles" | jq ".[] | select(.name == \"$role_name\")")
            
            if [ -n "$role_obj" ] && [ "$role_obj" != "null" ]; then
                roles_to_assign=$(echo "$roles_to_assign" | jq ". + [$role_obj]")
                log_info "Added role $role_name to assignment list"
            else
                log_warning "Role $role_name not found in available roles"
            fi
        fi
    done <<< "$(echo "$roles_array" | jq -r '.[]')"
    
    # Assign roles
    if [ "$(echo "$roles_to_assign" | jq '. | length')" -gt 0 ]; then
        local assign_response=$(api_request "POST" "$REALM_NAME/users/$user_id/role-mappings/realm" "$roles_to_assign")
        if [ $? -eq 0 ]; then
            log_success "Roles assigned successfully to service account $client_id"
        else
            log_error "Failed to assign roles to service account $client_id: $assign_response"
            return 1
        fi
    else
        log_warning "No valid roles to assign to service account $client_id"
    fi
}

# Function to create client scope
create_or_update_client_scope() {
    local scope_config="$1"
    
    local scope_name=$(echo "$scope_config" | jq -r '.name')
    log_info "Creating or updating client scope: $scope_name"
    
    # Check if scope exists
    local existing_scopes=$(api_request "GET" "$REALM_NAME/client-scopes")
    local existing_scope=$(echo "$existing_scopes" | jq ".[] | select(.name == \"$scope_name\")")
    
    if [ -n "$existing_scope" ] && [ "$existing_scope" != "null" ]; then
        log_info "Client scope $scope_name exists, updating..."
        
        # Get scope ID
        local scope_id=$(echo "$existing_scope" | jq -r '.id')
        
        # Update scope
        local update_response=$(api_request "PUT" "$REALM_NAME/client-scopes/$scope_id" "$scope_config")
        if [ $? -eq 0 ]; then
            log_success "Client scope $scope_name updated successfully"
        else
            log_error "Failed to update client scope $scope_name: $update_response"
            return 1
        fi
    else
        log_info "Client scope $scope_name does not exist, creating..."
        
        # Create scope
        local create_response=$(api_request "POST" "$REALM_NAME/client-scopes" "$scope_config")
        if [ $? -eq 0 ]; then
            log_success "Client scope $scope_name created successfully"
        else
            log_error "Failed to create client scope $scope_name: $create_response"
            return 1
        fi
    fi
}

# Function to configure service accounts from configuration file
configure_service_accounts() {
    local config_file="$1"
    
    log_info "Configuring service accounts from $config_file..."
    
    if [ ! -f "$config_file" ]; then
        log_error "Service accounts configuration file not found: $config_file"
        return 1
    fi
    
    # Read service accounts configuration
    local service_accounts=$(jq -c '.serviceAccounts[]' "$config_file")
    
    while IFS= read -r account; do
        local client_id=$(echo "$account" | jq -r '.clientId')
        local client_name=$(echo "$account" | jq -r '.clientName')
        local client_secret=$(echo "$account" | jq -r '.clientSecret')
        local description=$(echo "$account" | jq -r '.description')
        local assigned_roles=$(echo "$account" | jq -c '.assignedRoles')
        
        # Build client configuration
        local client_config=$(jq -n \
            --arg clientId "$client_id" \
            --arg name "$client_name" \
            --arg secret "$client_secret" \
            --arg description "$description" \
            '{
                clientId: $clientId,
                name: $name,
                description: $description,
                enabled: true,
                publicClient: false,
                clientAuthenticatorType: "client-secret",
                secret: $secret,
                serviceAccountsEnabled: true,
                standardFlowEnabled: false,
                implicitFlowEnabled: false,
                directAccessGrantsEnabled: false,
                authorizationServicesEnabled: false,
                redirectUris: [],
                webOrigins: [],
                protocol: "openid-connect",
                attributes: {
                    "access.token.lifespan": "300",
                    "client.secret.creation.time": (now | tostring)
                },
                defaultClientScopes: ["web-origins", "role_list", "profile", "roles", "email"],
                optionalClientScopes: ["address", "phone", "offline_access", "microprofile-jwt", "microservice-communication"]
            }')
        
        # Create or update client
        create_or_update_client "$client_config"
        
        # Assign roles to service account
        assign_roles_to_service_account "$client_id" "$assigned_roles"
        
    done <<< "$service_accounts"
}

# Function to setup complete realm configuration
setup_realm_configuration() {
    local realm_file="$IMPORT_DIR/eagle-realm.json"
    local service_accounts_file="$IMPORT_DIR/service-accounts-config.json"
    
    log_info "Setting up complete realm configuration..."
    
    # Initialize API connection
    if ! init_api_connection; then
        return 1
    fi
    
    # Load environment-specific configuration
    local env_file="$IMPORT_DIR/environments/${ENVIRONMENT}.env"
    if [ -f "$env_file" ]; then
        log_info "Loading environment configuration: $env_file"
        source "$env_file"
    fi
    
    # Create or update realm
    create_or_update_realm "$realm_file"
    
    # Wait for realm to be fully initialized
    sleep 3
    
    # Create realm roles from realm configuration
    local realm_roles=$(jq -c '.roles.realm[]' "$realm_file")
    while IFS= read -r role; do
        if [ -n "$role" ] && [ "$role" != "null" ]; then
            create_or_update_realm_role "$role"
        fi
    done <<< "$realm_roles"
    
    # Create client scopes from realm configuration
    local client_scopes=$(jq -c '.clientScopes[]' "$realm_file")
    while IFS= read -r scope; do
        if [ -n "$scope" ] && [ "$scope" != "null" ]; then
            create_or_update_client_scope "$scope"
        fi
    done <<< "$client_scopes"
    
    # Configure service accounts
    configure_service_accounts "$service_accounts_file"
    
    log_success "Realm configuration setup completed"
}

# Function to validate configuration
validate_configuration() {
    log_info "Validating Keycloak configuration..."
    
    # Run validation script
    local validation_script="$SCRIPT_DIR/validate-keycloak.sh"
    if [ -f "$validation_script" ]; then
        bash "$validation_script" -u "$KEYCLOAK_URL" -r "$REALM_NAME" -e "$ENVIRONMENT"
    else
        log_warning "Validation script not found: $validation_script"
    fi
}

# Function to backup current configuration
backup_configuration() {
    local backup_dir="$KEYCLOAK_DIR/backups"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$backup_dir/realm-backup-$timestamp.json"
    
    log_info "Creating configuration backup..."
    
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"
    
    # Initialize API connection if not already done
    if [ -z "$ADMIN_TOKEN" ]; then
        init_api_connection
    fi
    
    # Export realm configuration
    local realm_export=$(api_request "GET" "$REALM_NAME")
    
    if [ $? -eq 0 ] && [ -n "$realm_export" ]; then
        echo "$realm_export" | jq '.' > "$backup_file"
        log_success "Configuration backup saved to: $backup_file"
    else
        log_error "Failed to create configuration backup"
        return 1
    fi
}

# Main function for script execution
main() {
    local action="${1:-setup}"
    
    case "$action" in
        "setup")
            setup_realm_configuration
            ;;
        "validate")
            validate_configuration
            ;;
        "backup")
            backup_configuration
            ;;
        "help")
            echo "Usage: $0 [setup|validate|backup|help]"
            echo "  setup    - Setup complete realm configuration"
            echo "  validate - Validate current configuration"
            echo "  backup   - Backup current configuration"
            echo "  help     - Show this help message"
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Export functions for use in other scripts
export -f log_info log_success log_warning log_error
export -f init_api_connection get_admin_token api_request
export -f create_or_update_realm create_or_update_client create_or_update_realm_role
export -f assign_roles_to_service_account create_or_update_client_scope
export -f configure_service_accounts setup_realm_configuration
export -f validate_configuration backup_configuration

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi