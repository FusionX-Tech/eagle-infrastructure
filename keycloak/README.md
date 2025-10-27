# Keycloak Configuration for Eagle Microservices

This directory contains the complete Keycloak configuration for secure microservice communication in the Eagle platform.

## Overview

The configuration implements OAuth2 Client Credentials Flow for service-to-service authentication using Keycloak as the Identity Provider (IdP). Each microservice acts as both an OAuth2 client (to obtain tokens) and a resource server (to validate tokens).

## Directory Structure

```
infra/keycloak/
├── import/
│   ├── eagle-realm.json              # Main realm configuration
│   ├── service-accounts-config.json  # Service accounts documentation
│   └── environments/
│       ├── dev.env                   # Development environment variables
│       └── prod.env                  # Production environment variables
├── scripts/
│   ├── setup-keycloak.sh            # Linux/macOS setup script
│   ├── setup-keycloak.ps1           # Windows PowerShell setup script
│   ├── validate-keycloak.sh         # Configuration validation script
│   └── init-db.sql                  # Database initialization script
├── docker-compose.keycloak.yml       # Docker Compose for Keycloak
└── README.md                         # This file
```

## Quick Start

### 1. Using Docker Compose (Recommended for Development)

```bash
# Start Keycloak with PostgreSQL
cd infra/keycloak
docker-compose -f docker-compose.keycloak.yml up -d

# Wait for Keycloak to be ready (check logs)
docker-compose -f docker-compose.keycloak.yml logs -f keycloak

# The realm will be automatically imported on startup
```

### 2. Manual Setup

If you have an existing Keycloak instance:

```bash
# Linux/macOS
cd infra/keycloak/scripts
chmod +x setup-keycloak.sh
./setup-keycloak.sh

# Windows PowerShell
cd infra\keycloak\scripts
.\setup-keycloak.ps1
```

### 3. Validation

After setup, validate the configuration:

```bash
# Linux/macOS
cd infra/keycloak/scripts
chmod +x validate-keycloak.sh
./validate-keycloak.sh

# Windows PowerShell
# Use the validation features in setup-keycloak.ps1
```

## Configuration Details

### Realm Configuration

The `eagle-realm.json` file contains:

- **Realm**: `eagle-dev` (development) / `eagle-prod` (production)
- **Token Lifespan**: 300 seconds (5 minutes)
- **Security Policies**: Brute force protection, SSL requirements
- **Roles**: Microservice-specific roles and permissions

### Service Accounts

Each microservice has a dedicated service account:

| Service | Client ID | Roles |
|---------|-----------|-------|
| ms-customer | ms-customer | MICROSERVICE, CUSTOMER_READ, CUSTOMER_WRITE, ALERT_SEND |
| ms-alert | ms-alert | MICROSERVICE, ALERT_SEND, CUSTOMER_READ |
| ms-enrichment | ms-enrichment | MICROSERVICE, ENRICHMENT_READ, ENRICHMENT_WRITE, CUSTOMER_READ |
| ms-orchestrator | ms-orchestrator | MICROSERVICE, ORCHESTRATOR_EXECUTE, CUSTOMER_READ, ALERT_SEND |

### Roles and Permissions

- **MICROSERVICE**: Base role for service-to-service communication
- **CUSTOMER_READ**: Permission to read customer data
- **CUSTOMER_WRITE**: Permission to modify customer data
- **ALERT_SEND**: Permission to send alerts
- **ENRICHMENT_READ/WRITE**: Permission to access enrichment data
- **ORCHESTRATOR_EXECUTE**: Permission to execute workflows

## Environment Configuration

### Development Environment

```bash
# Source the development environment
source infra/keycloak/import/environments/dev.env

# Key variables:
KEYCLOAK_ISSUER_URI=http://localhost:8080/realms/eagle-dev
ACCESS_TOKEN_LIFESPAN=300
```

### Production Environment

```bash
# Source the production environment
source infra/keycloak/import/environments/prod.env

# Key variables:
KEYCLOAK_ISSUER_URI=https://keycloak.fusionx.pro/realms/eagle-prod
ACCESS_TOKEN_LIFESPAN=180  # More restrictive
```

## Script Usage

### Setup Script Options

```bash
# Linux/macOS
./setup-keycloak.sh [OPTIONS]

Options:
  -u, --url URL           Keycloak URL (default: http://localhost:8080)
  -a, --admin USER        Admin username (default: admin)
  -p, --password PASS     Admin password (default: admin123)
  -r, --realm REALM       Realm name (default: eagle-dev)
  -e, --environment ENV   Environment (dev/prod) (default: dev)
  -h, --help              Show help message

# Windows PowerShell
.\setup-keycloak.ps1 [OPTIONS]

Parameters:
  -KeycloakUrl URL        Keycloak URL
  -AdminUser USER         Admin username
  -AdminPassword PASS     Admin password
  -RealmName REALM        Realm name
  -Environment ENV        Environment
  -Help                   Show help message
```

### Validation Script Options

```bash
./validate-keycloak.sh [OPTIONS]

Options:
  -u, --url URL           Keycloak URL (default: http://localhost:8080)
  -r, --realm REALM       Realm name (default: eagle-dev)
  -e, --environment ENV   Environment (dev/prod) (default: dev)
  -h, --help              Show help message
```

## Integration with Microservices

### Spring Boot Configuration

Add to your microservice's `application.yml`:

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          keycloak:
            client-id: ${MS_CLIENT_ID}
            client-secret: ${MS_CLIENT_SECRET}
            authorization-grant-type: client_credentials
            scope: microservice-communication
        provider:
          keycloak:
            token-uri: ${KEYCLOAK_ISSUER_URI}/protocol/openid-connect/token
      resourceserver:
        jwt:
          issuer-uri: ${KEYCLOAK_ISSUER_URI}
          jwk-set-uri: ${KEYCLOAK_ISSUER_URI}/protocol/openid-connect/certs
```

### Environment Variables

Set these environment variables for each microservice:

```bash
# Common
KEYCLOAK_ISSUER_URI=http://localhost:8080/realms/eagle-dev

# Service-specific (example for ms-customer)
MS_CLIENT_ID=ms-customer
MS_CLIENT_SECRET=customer-secret
```

## Security Considerations

### Development Environment

- Uses HTTP for local development
- Longer token lifespans for easier debugging
- Less restrictive brute force protection

### Production Environment

- Requires HTTPS/TLS
- Shorter token lifespans (3 minutes)
- Stricter security policies
- Enhanced brute force protection

### Best Practices

1. **Secret Management**: Use secure secret management systems in production
2. **Network Security**: Ensure Keycloak is only accessible from authorized networks
3. **Monitoring**: Monitor authentication failures and token usage
4. **Regular Updates**: Keep Keycloak updated to the latest security patches
5. **Backup**: Regular backup of Keycloak database and configuration

## Troubleshooting

### Common Issues

1. **Connection Refused**
   ```bash
   # Check if Keycloak is running
   curl http://localhost:8080/health/ready
   ```

2. **Token Generation Fails**
   ```bash
   # Test token generation manually
   curl -X POST http://localhost:8080/realms/eagle-dev/protocol/openid-connect/token \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=client_credentials" \
     -d "client_id=ms-customer" \
     -d "client_secret=customer-secret"
   ```

3. **Token Validation Fails**
   ```bash
   # Check JWKS endpoint
   curl http://localhost:8080/realms/eagle-dev/protocol/openid-connect/certs
   ```

### Logs

Check Keycloak logs for detailed error information:

```bash
# Docker Compose
docker-compose -f docker-compose.keycloak.yml logs keycloak

# Standalone Keycloak
tail -f /opt/keycloak/data/log/keycloak.log
```

## Monitoring and Metrics

Keycloak exposes metrics at:
- Health: `http://localhost:8080/health`
- Metrics: `http://localhost:8080/metrics`

Key metrics to monitor:
- `keycloak_logins_total`
- `keycloak_login_failures_total`
- `keycloak_tokens_total`
- `keycloak_response_time_seconds`

## Backup and Recovery

### Database Backup

```bash
# PostgreSQL backup
docker exec eagle-keycloak-db pg_dump -U keycloak keycloak > keycloak-backup.sql

# Restore
docker exec -i eagle-keycloak-db psql -U keycloak keycloak < keycloak-backup.sql
```

### Configuration Export

```bash
# Export realm configuration
curl -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://localhost:8080/admin/realms/eagle-dev > eagle-realm-backup.json
```

## Support

For issues related to this configuration:

1. Check the validation script output
2. Review Keycloak logs
3. Verify network connectivity
4. Ensure all required environment variables are set
5. Check the microservice logs for authentication errors

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OAuth2 Client Credentials Flow](https://tools.ietf.org/html/rfc6749#section-4.4)
- [Spring Security OAuth2](https://docs.spring.io/spring-security/reference/servlet/oauth2/index.html)
- [JWT Specification](https://tools.ietf.org/html/rfc7519)