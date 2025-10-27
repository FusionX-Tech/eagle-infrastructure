#!/bin/bash

# Keycloak Integration Script for Kong API Gateway
# This script fetches the public key from Keycloak and updates Kong configuration

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-eagle-dev}"
KONG_ADMIN_URL="${KONG_ADMIN_URL:-http://kong:8001}"

echo "🔐 Configuring Keycloak integration with Kong..."

# Wait for Keycloak to be ready
echo "⏳ Waiting for Keycloak to be ready..."
until curl -sf "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/.well-known/openid_configuration" > /dev/null; do
    echo "Waiting for Keycloak..."
    sleep 5
done

# Fetch Keycloak public key
echo "🔑 Fetching Keycloak public key..."
KEYCLOAK_PUBLIC_KEY=$(curl -s "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" | jq -r '.public_key')

if [ -z "$KEYCLOAK_PUBLIC_KEY" ] || [ "$KEYCLOAK_PUBLIC_KEY" = "null" ]; then
    echo "❌ Failed to fetch Keycloak public key"
    exit 1
fi

# Format the public key for Kong
PUBLIC_KEY_FORMATTED="-----BEGIN PUBLIC KEY-----\n${KEYCLOAK_PUBLIC_KEY}\n-----END PUBLIC KEY-----"

echo "✅ Keycloak public key fetched successfully"

# Wait for Kong to be ready
echo "⏳ Waiting for Kong Admin API to be ready..."
until curl -sf "${KONG_ADMIN_URL}/status" > /dev/null; do
    echo "Waiting for Kong..."
    sleep 5
done

# Create or update JWT credentials for consumers
echo "🔧 Configuring JWT credentials in Kong..."

# Configure JWT for eagle-frontend consumer
curl -X POST "${KONG_ADMIN_URL}/consumers/eagle-frontend/jwt" \
    -H "Content-Type: application/json" \
    -d "{
        \"key\": \"${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}\",
        \"algorithm\": \"RS256\",
        \"rsa_public_key\": \"${PUBLIC_KEY_FORMATTED}\"
    }" || echo "JWT credential for eagle-frontend may already exist"

# Configure JWT for eagle-mobile consumer
curl -X POST "${KONG_ADMIN_URL}/consumers/eagle-mobile/jwt" \
    -H "Content-Type: application/json" \
    -d "{
        \"key\": \"${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}\",
        \"algorithm\": \"RS256\",
        \"rsa_public_key\": \"${PUBLIC_KEY_FORMATTED}\"
    }" || echo "JWT credential for eagle-mobile may already exist"

# Create API key for internal services
echo "🔑 Creating API key for internal services..."
curl -X POST "${KONG_ADMIN_URL}/consumers/eagle-internal/key-auth" \
    -H "Content-Type: application/json" \
    -d "{
        \"key\": \"eagle-internal-api-key-2024\"
    }" || echo "API key for eagle-internal may already exist"

# Verify configuration
echo "🔍 Verifying Kong configuration..."
KONG_STATUS=$(curl -s "${KONG_ADMIN_URL}/status" | jq -r '.database.reachable')

if [ "$KONG_STATUS" = "true" ]; then
    echo "✅ Kong is configured and running successfully"
    
    # Display configuration summary
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Keycloak URL: ${KEYCLOAK_URL}"
    echo "  Keycloak Realm: ${KEYCLOAK_REALM}"
    echo "  Kong Admin URL: ${KONG_ADMIN_URL}"
    echo "  JWT Issuer: ${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
    echo ""
    echo "🔗 Available Routes:"
    curl -s "${KONG_ADMIN_URL}/routes" | jq -r '.data[] | "  \(.name): \(.methods[]) \(.paths[])"'
    
else
    echo "❌ Kong configuration verification failed"
    exit 1
fi

echo "🎉 Keycloak integration with Kong completed successfully!"