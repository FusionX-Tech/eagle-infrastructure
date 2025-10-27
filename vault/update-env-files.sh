#!/bin/bash

set -e

echo "🔐 Updating environment files for Vault integration..."

# Function to update or add environment variable
update_env_var() {
    local file=$1
    local var_name=$2
    local var_value=$3
    
    if [ -f "$file" ]; then
        if grep -q "^${var_name}=" "$file"; then
            # Update existing variable
            sed -i "s/^${var_name}=.*/${var_name}=${var_value}/" "$file"
        else
            # Add new variable
            echo "${var_name}=${var_value}" >> "$file"
        fi
        echo "  ✅ Updated ${var_name} in ${file}"
    else
        echo "  ⚠️  File ${file} not found, creating..."
        echo "${var_name}=${var_value}" > "$file"
    fi
}

# Get Vault credentials from running container
echo "📋 Retrieving Vault credentials..."

# Wait for Vault to be ready
echo "⏳ Waiting for Vault to be ready..."
until docker exec fx-vault vault status > /dev/null 2>&1; do
    echo "  Waiting for Vault..."
    sleep 2
done

# Get AppRole credentials
ROLE_ID=$(docker exec fx-vault vault read -field=role_id auth/approle/role/microservices-role/role-id 2>/dev/null || echo "")
SECRET_ID=$(docker exec fx-vault vault write -field=secret_id auth/approle/role/microservices-role/secret-id 2>/dev/null || echo "")

if [ -z "$ROLE_ID" ] || [ -z "$SECRET_ID" ]; then
    echo "❌ Failed to retrieve Vault credentials. Make sure Vault is properly initialized."
    exit 1
fi

echo "✅ Retrieved Vault credentials successfully"

# Update main .env file
echo "📝 Updating main .env file..."
update_env_var ".env" "VAULT_ADDR" "http://vault:8200"
update_env_var ".env" "VAULT_ROOT_TOKEN" "myroot"
update_env_var ".env" "VAULT_ROLE_ID" "$ROLE_ID"
update_env_var ".env" "VAULT_SECRET_ID" "$SECRET_ID"

# Update microservice .env files
MICROSERVICES=("ms-alert" "ms-customer" "ms-transaction" "ms-api" "ms-enrichment" "ms-orchestrator")

for service in "${MICROSERVICES[@]}"; do
    env_file="services/${service}/.env"
    echo "📝 Updating ${env_file}..."
    
    update_env_var "$env_file" "VAULT_ADDR" "http://vault:8200"
    update_env_var "$env_file" "VAULT_ROLE_ID" "$ROLE_ID"
    update_env_var "$env_file" "VAULT_SECRET_ID" "$SECRET_ID"
    update_env_var "$env_file" "VAULT_DYNAMIC_DB_ENABLED" "true"
    update_env_var "$env_file" "VAULT_REDIS_ENABLED" "true"
    update_env_var "$env_file" "VAULT_AWS_ENABLED" "true"
    
    # Enable management endpoints only for development
    if [ "$1" = "--enable-management" ]; then
        update_env_var "$env_file" "VAULT_MANAGEMENT_ENABLED" "true"
    else
        update_env_var "$env_file" "VAULT_MANAGEMENT_ENABLED" "false"
    fi
done

echo ""
echo "✅ All environment files updated successfully!"
echo ""
echo "🔐 Vault Configuration Summary:"
echo "  Vault URL: http://localhost:8200"
echo "  Root Token: myroot"
echo "  Role ID: $ROLE_ID"
echo "  Secret ID: $SECRET_ID"
echo ""
echo "📝 Next steps:"
echo "  1. Restart microservices to pick up new Vault configuration"
echo "  2. Verify Vault connectivity using health endpoints"
echo "  3. Test dynamic database credentials rotation"
echo ""
echo "🔧 Commands to restart services:"
echo "  docker-compose restart ms-alert ms-customer ms-transaction ms-api ms-enrichment ms-orchestrator"