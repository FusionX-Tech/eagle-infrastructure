# Keycloak Configuration and Automation

This directory contains the Keycloak configuration and automation scripts for the Eagle microservices architecture.

## Overview

Keycloak is used as the Identity Provider (IdP) for secure communication between microservices using OAuth2 Client Credentials Flow. This setup includes comprehensive automation scripts for setup, validation, and maintenance.

## Structure

```
keycloak/
├── docker-compose.keycloak.yml     # Docker Compose configuration
├── import/                         # Configuration files
│   ├── eagle-realm.json           # Realm configuration
│   ├── service-accounts-config.json # Service accounts configuration
│   └── environments/              # Environment-specific configs
│       ├── dev.env                # Development environment
│       └── prod.env               # Production environment
├── scripts/                        # Automation scripts
│   ├── setup-automation.sh        # Main automation orchestrator (Bash)
│   ├── setup-automation.ps1       # Main automation orchestrator (PowerShell)
│   ├── keycloak-admin-api.sh      # Admin API operations (Bash)
│   ├── keycloak-admin-api.ps1     # Admin API operations (PowerShell)
│   ├── validate-keycloak.sh       # Enhanced validation (Bash)
│   ├── validate-keycloak.ps1      # Enhanced validation (PowerShell)
│   ├── setup-keycloak.sh          # Legacy setup script (Bash)
│   └── setup-keycloak.ps1         # Legacy setup script (PowerShell)
├── backups/                        # Configuration backups (auto-created)
└── Makefile                        # Convenient commands
```

## Quick Start

### Automated Setup (Recommended)

1. **Start Keycloak:**
   ```bash
   make start
   ```

2. **Automated setup (no prompts):**
   ```bash
   make setup-auto
   ```

3. **Validate configuration:**
   ```bash
   make validate-config
   ```

### Interactive Setup

1. **Start Keycloak:**
   ```bash
   make start
   ```

2. **Interactive setup:**
   ```bash
   make setup
   ```

3. **Validate configuration:**
   ```bash
   make validate
   ```

## Automation Scripts

### Main Orchestrator Scripts

#### `setup-automation.sh` / `setup-automation.ps1`
Comprehensive automation orchestrator that handles the complete setup process:

**Features:**
- Prerequisites checking
- Keycloak health monitoring
- Configuration backup (optional)
- Realm and service account setup
- Configuration validation
- Setup reporting
- Next steps guidance

**Usage:**
```bash
# Interactive setup
./scripts/setup-automation.sh

# Automated setup (no prompts)
./scripts/setup-automation.sh --auto-approve

# Production setup
./scripts/setup-automation.sh --environment prod --auto-approve

# Skip validation and backup
./scripts/setup-automation.sh --skip-validation --no-backup
```

**PowerShell:**
```powershell
# Interactive setup
.\scripts\setup-automation.ps1

# Automated setup
.\scripts\setup-automation.ps1 -AutoApprove

# Production setup
.\scripts\setup-automation.ps1 -Environment prod -AutoApprove
```

### Admin API Scripts

#### `keycloak-admin-api.sh` / `keycloak-admin-api.ps1`
Direct interaction with Keycloak Admin API for programmatic configuration:

**Features:**
- Realm creation/update
- Client management
- Role management
- Service account configuration
- Configuration backup
- Validation

**Usage:**
```bash
# Setup complete configuration
./scripts/keycloak-admin-api.sh setup

# Validate configuration
./scripts/keycloak-admin-api.sh validate

# Backup configuration
./scripts/keycloak-admin-api.sh backup
```

### Enhanced Validation Scripts

#### `validate-keycloak.sh` / `validate-keycloak.ps1`
Comprehensive validation of Keycloak configuration:

**Validation Checks:**
- Keycloak connectivity
- Realm configuration
- Service account functionality
- Token generation and validation
- Security configuration
- Environment-specific settings

**Usage:**
```bash
# Validate current environment
./scripts/validate-keycloak.sh

# Validate specific environment
./scripts/validate-keycloak.sh --environment prod --url https://keycloak.example.com
```

## Configuration

### Environment Variables

- `KEYCLOAK_URL`: Keycloak server URL (default: http://localhost:8080)
- `KEYCLOAK_ADMIN_USER`: Admin username (default: admin)
- `KEYCLOAK_ADMIN_PASSWORD`: Admin password (default: admin123)
- `REALM_NAME`: Realm name (default: eagle-dev)
- `ENVIRONMENT`: Environment (dev/prod) (default: dev)

### Service Accounts

The following service accounts are automatically configured:

- **ms-customer**: Customer microservice
  - Roles: MICROSERVICE, CUSTOMER_READ, CUSTOMER_WRITE, ALERT_SEND
  - Client Secret: customer-secret (dev)
- **ms-alert**: Alert microservice
  - Roles: MICROSERVICE, ALERT_SEND, CUSTOMER_READ
  - Client Secret: alert-secret (dev)
- **ms-enrichment**: Enrichment microservice
  - Roles: MICROSERVICE, ENRICHMENT_READ, ENRICHMENT_WRITE, CUSTOMER_READ
  - Client Secret: enrichment-secret (dev)
- **ms-orchestrator**: Orchestrator microservice
  - Roles: MICROSERVICE, ORCHESTRATOR_EXECUTE, CUSTOMER_READ, ALERT_SEND
  - Client Secret: orchestrator-secret (dev)

## Make Commands

### Basic Operations
```bash
make help              # Show all available commands
make start             # Start Keycloak using Docker Compose
make stop              # Stop Keycloak containers
make status            # Show container status and health
make logs              # Show Keycloak logs
make clean             # Clean up containers and volumes
```

### Setup and Configuration
```bash
make setup             # Interactive setup with prompts
make setup-auto        # Automated setup without prompts
make setup-legacy      # Use legacy setup script
make validate          # Basic validation
make validate-config   # Enhanced validation
make backup            # Backup database
make backup-config     # Backup configuration via Admin API
```

### Development Workflows
```bash
make dev               # Complete development setup (start + setup + validate)
make dev-auto          # Automated development setup
make test              # Test service account token generation
```

### Production Workflows
```bash
make prod-setup        # Production setup
make prod-auto         # Automated production setup
```

### Admin API Operations
```bash
make admin-api         # Interactive Admin API operations
make backup-config     # Backup via Admin API
make validate-config   # Enhanced validation
```

### Windows PowerShell
```bash
make ps-setup          # Show PowerShell setup command
make ps-validate       # Show PowerShell validation command
make ps-backup         # Show PowerShell backup command
```

## Usage Examples

### Development Environment

```bash
# Quick development setup
make start && make dev-auto

# Manual development setup with validation
make start
make setup
make validate-config
```

### Production Environment

```bash
# Production setup
ENVIRONMENT=prod KEYCLOAK_URL=https://keycloak.fusionx.pro make prod-auto

# Manual production setup
./scripts/setup-automation.sh \
  --environment prod \
  --url https://keycloak.fusionx.pro \
  --realm eagle-prod \
  --auto-approve
```

### Configuration Management

```bash
# Backup current configuration
make backup-config

# Validate configuration
make validate-config

# Admin API operations
make admin-api
```

## Endpoints

After setup, the following endpoints will be available:

- **Admin Console**: http://localhost:8080/admin
- **Token Endpoint**: http://localhost:8080/realms/eagle-dev/protocol/openid-connect/token
- **JWKS Endpoint**: http://localhost:8080/realms/eagle-dev/protocol/openid-connect/certs
- **Health Check**: http://localhost:8080/health/ready
- **Issuer URI**: http://localhost:8080/realms/eagle-dev

## Testing Service Accounts

### Using Make Command
```bash
make test
```

### Manual Testing
```bash
# Test ms-customer token generation
curl -X POST http://localhost:8080/realms/eagle-dev/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=ms-customer" \
  -d "client_secret=customer-secret" \
  -d "scope=microservice-communication"
```

### Token Validation
```bash
# The validation scripts automatically test token generation for all service accounts
./scripts/validate-keycloak.sh
```

## Troubleshooting

### Common Issues

1. **Keycloak not starting**: 
   ```bash
   make logs
   make status
   ```

2. **Setup fails**: 
   - Ensure Keycloak is running: `make status`
   - Check prerequisites: `make check-deps`
   - Review setup logs

3. **Token generation fails**: 
   - Verify service account credentials
   - Run validation: `make validate-config`
   - Check Keycloak logs: `make logs`

4. **Permission issues on scripts**:
   ```bash
   chmod +x scripts/*.sh
   ```

### Validation and Diagnostics

```bash
# Comprehensive validation
make validate-config

# Check dependencies
make check-deps

# Show configuration info
make info

# Test token generation
make test
```

### Logs and Monitoring

```bash
# View Keycloak logs
make logs

# View database logs
make logs-db

# Check health
curl http://localhost:8080/health/ready
```

## Production Deployment

### Security Considerations

1. **Use HTTPS**: Update `KEYCLOAK_URL` to use HTTPS
2. **Secure Secrets**: Use environment variables or secret management
3. **Token Lifespans**: Configure appropriate token lifespans in prod.env
4. **SSL Requirements**: Set `SSL_REQUIRED=all` in production
5. **Brute Force Protection**: Enable and configure appropriately

### Production Setup Steps

1. **Update production environment file**:
   ```bash
   # Edit import/environments/prod.env
   KEYCLOAK_ISSUER_URI=https://keycloak.fusionx.pro/realms/eagle-prod
   SSL_REQUIRED=all
   ACCESS_TOKEN_LIFESPAN=180
   ```

2. **Deploy with production settings**:
   ```bash
   ENVIRONMENT=prod KEYCLOAK_URL=https://keycloak.fusionx.pro make prod-auto
   ```

3. **Validate production setup**:
   ```bash
   ENVIRONMENT=prod KEYCLOAK_URL=https://keycloak.fusionx.pro make validate-config
   ```

## Backup and Restore

### Configuration Backup
```bash
# Backup configuration via Admin API
make backup-config

# Manual backup
./scripts/keycloak-admin-api.sh backup
```

### Database Backup
```bash
# Backup database
make backup-db

# Restore database
make restore
```

## Development Workflow

### Initial Setup
```bash
# Start fresh development environment
make clean
make start
make dev-auto
```

### Daily Development
```bash
# Start existing environment
make start
make status
```

### Testing Changes
```bash
# Validate after configuration changes
make validate-config

# Test service accounts
make test
```

## Integration with Microservices

After Keycloak setup, configure your microservices with:

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          keycloak:
            client-id: ms-customer
            client-secret: ${MS_CUSTOMER_CLIENT_SECRET}
            authorization-grant-type: client_credentials
            scope: microservice-communication
        provider:
          keycloak:
            token-uri: ${KEYCLOAK_ISSUER_URI}/protocol/openid-connect/token
      resourceserver:
        jwt:
          issuer-uri: ${KEYCLOAK_ISSUER_URI}
```

## Monitoring and Maintenance

### Regular Tasks
- Monitor Keycloak logs for authentication failures
- Rotate client secrets periodically
- Update token lifespans as needed
- Backup configurations before changes

### Metrics and Alerting
- Set up monitoring for token generation failures
- Alert on authentication anomalies
- Monitor Keycloak service health

## Support

For issues or questions:
1. Check the troubleshooting section
2. Run validation scripts
3. Review Keycloak logs
4. Consult Keycloak documentation