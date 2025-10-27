#!/bin/bash

set -e

echo "🔐 Initializing HashiCorp Vault..."

# Wait for Vault to be ready
until vault status > /dev/null 2>&1; do
  echo "Waiting for Vault to be ready..."
  sleep 2
done

echo "✅ Vault is ready, starting configuration..."

# Enable KV secrets engine v2
echo "📝 Enabling KV secrets engine..."
vault secrets enable -version=2 -path=secret kv || echo "KV engine already enabled"

# Enable database secrets engine
echo "🗄️ Enabling database secrets engine..."
vault secrets enable database || echo "Database engine already enabled"

# Configure PostgreSQL database connection
echo "🔗 Configuring PostgreSQL connection..."
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/eagle?sslmode=disable" \
    allowed_roles="eagle-db-role,eagle-readonly-role" \
    username="${POSTGRES_USER:-eagle}" \
    password="${POSTGRES_PASSWORD:-eagle123}"

# Create database roles
echo "👤 Creating database roles..."
vault write database/roles/eagle-db-role \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
        GRANT CREATE ON SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

vault write database/roles/eagle-readonly-role \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

# Create policies
echo "📋 Creating policies..."
vault policy write microservices-policy /vault/policies/microservices-policy.hcl
vault policy write admin-policy /vault/policies/admin-policy.hcl

# Enable AppRole auth method
echo "🔑 Enabling AppRole authentication..."
vault auth enable approle || echo "AppRole already enabled"

# Create AppRole for microservices
echo "🤖 Creating AppRole for microservices..."
vault write auth/approle/role/microservices-role \
    token_policies="microservices-policy" \
    token_ttl=1h \
    token_max_ttl=4h \
    bind_secret_id=true

# Get role-id for microservices
ROLE_ID=$(vault read -field=role_id auth/approle/role/microservices-role/role-id)
echo "📋 Microservices Role ID: $ROLE_ID"

# Generate secret-id for microservices
SECRET_ID=$(vault write -field=secret_id auth/approle/role/microservices-role/secret-id)
echo "🔐 Microservices Secret ID: $SECRET_ID"

# Store microservice credentials
echo "💾 Storing microservice credentials..."

# Database credentials (will be replaced by dynamic secrets)
vault kv put secret/microservices/database \
    host="postgres" \
    port="5432" \
    database="eagle" \
    username="${POSTGRES_USER:-eagle}" \
    password="${POSTGRES_PASSWORD:-eagle123}" \
    replica1_host="postgres-replica-1" \
    replica1_port="5432" \
    replica2_host="postgres-replica-2" \
    replica2_port="5432"

# Redis credentials
vault kv put secret/redis/cluster \
    master_host="redis-master" \
    master_port="6379" \
    replica_host="redis-replica" \
    replica_port="6379" \
    password=""

# Keycloak credentials
vault kv put secret/microservices/keycloak \
    server_url="http://keycloak:8080" \
    realm="eagle-dev" \
    client_id="eagle-backend" \
    client_secret="${KEYCLOAK_CLIENT_SECRET:-eagle-secret}"

# AWS/LocalStack credentials
vault kv put secret/aws/credentials \
    access_key_id="${AWS_ACCESS_KEY_ID:-test}" \
    secret_access_key="${AWS_SECRET_ACCESS_KEY:-test}" \
    region="${AWS_REGION:-us-east-1}" \
    endpoint="http://localstack:4566"

# External API credentials
vault kv put secret/external-apis/portal-transparencia \
    base_url="https://api.portaldatransparencia.gov.br" \
    api_key="${PORTAL_TRANSPARENCIA_API_KEY:-}" \
    timeout="30000"

# JWT signing secrets
vault kv put secret/jwt/signing \
    secret_key="${JWT_SECRET_KEY:-eagle-jwt-secret-key-2024}" \
    algorithm="HS256" \
    expiration="3600"

# Store AppRole credentials for microservices
vault kv put secret/microservices/vault-auth \
    role_id="$ROLE_ID" \
    secret_id="$SECRET_ID" \
    vault_addr="http://vault:8200"

echo "✅ Vault setup completed successfully!"
echo "🔐 Vault UI available at: http://localhost:8200"
echo "🔑 Root token: ${VAULT_ROOT_TOKEN:-myroot}"
echo "📋 Microservices Role ID: $ROLE_ID"
echo "🔐 Microservices Secret ID: $SECRET_ID"