# Pact Broker - Contract Testing Infrastructure

## Overview

Pact Broker é o servidor centralizado que armazena e gerencia contratos de API entre microsserviços do Eagle. Ele permite verificar compatibilidade entre consumers e providers antes do deploy, reduzindo drasticamente a necessidade de testes E2E.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Pact Broker                            │
│  (Armazena contratos + verifica compatibilidade)           │
│  http://localhost:9292                                      │
└─────────────────────────────────────────────────────────────┘
         ▲                                    │
         │ Publica Contrato                   │ Baixa Contrato
         │                                    ▼
┌────────────────────┐              ┌────────────────────┐
│   MS Consumer      │              │   MS Provider      │
│  (ms-alert)        │              │   (ms-customer)    │
│                    │              │                    │
│  Consumer Test     │              │  Provider Test     │
│  (Define contrato) │              │  (Verifica impl.)  │
└────────────────────┘              └────────────────────┘
```

## Components

### PostgreSQL (postgres-pact)
- **Port:** 5436 (external), 5432 (internal)
- **Database:** pact_broker
- **User:** fusionx (from .env)
- **Purpose:** Armazena contratos, verificações e histórico

### Pact Broker
- **Port:** 9292
- **Image:** pactfoundation/pact-broker:2.107.1
- **Purpose:** Interface web e API para gerenciar contratos

## Quick Start

### 1. Ensure Eagle Network Exists

```bash
# Create network if it doesn't exist
docker network create eagle-network
```

### 2. Start Pact Broker

```bash
# From Eagle/eagle-infrastructure/pact-broker directory
docker-compose up -d

# Or from Eagle/eagle-infrastructure directory
docker-compose -f pact-broker/docker-compose.yml up -d
```

### 3. Verify Deployment

```bash
# Check services are running
docker-compose ps

# Check health
curl http://localhost:9292/diagnostic/status/heartbeat

# Expected response: {"ok":true}
```

### 4. Access Web UI

Open browser: http://localhost:9292

**Credentials:**
- Username: `pact_user`
- Password: `pact_secure_password_2024` (from .env)

**Read-only access:**
- Username: `pact_reader`
- Password: `pact_reader_password_2024` (from .env)

## Environment Variables

All environment variables are defined in `Eagle/eagle-infrastructure/.env`:

```bash
# Pact Broker Configuration
PACT_BROKER_URL=http://localhost:9292
PACT_BROKER_USERNAME=pact_user
PACT_BROKER_PASSWORD=pact_secure_password_2024
PACT_BROKER_READ_ONLY_USERNAME=pact_reader
PACT_BROKER_READ_ONLY_PASSWORD=pact_reader_password_2024
PACT_BROKER_TOKEN=pact_token_secure_2024
```

### Security Notes

⚠️ **IMPORTANT:** Change default passwords in production!

1. Update passwords in `.env` file
2. Restart Pact Broker: `docker-compose restart pact-broker`
3. Update CI/CD secrets with new credentials

## Authentication

### Basic Auth (Web UI)

```bash
# Full access
curl -u pact_user:pact_secure_password_2024 http://localhost:9292/

# Read-only access
curl -u pact_reader:pact_reader_password_2024 http://localhost:9292/
```

### Token Auth (CI/CD)

```bash
# Using token for automated tools
curl -H "Authorization: Bearer pact_token_secure_2024" \
  http://localhost:9292/pacts/provider/ms-customer/consumer/ms-alert/latest
```

## Health Checks

### Heartbeat Endpoint

```bash
curl http://localhost:9292/diagnostic/status/heartbeat
# Response: {"ok":true}
```

### Full Diagnostic

```bash
curl http://localhost:9292/diagnostic/status/dependencies
# Shows database connection status
```

### PostgreSQL Health

```bash
# Check PostgreSQL is accepting connections
docker exec postgres-pact pg_isready -U fusionx
# Response: /var/run/postgresql:5432 - accepting connections
```

## Common Operations

### View All Contracts

```bash
# List all pacts
curl http://localhost:9292/pacts/latest

# View specific pact
curl http://localhost:9292/pacts/provider/ms-customer/consumer/ms-alert/latest
```

### Publish Contract (Manual)

```bash
# From consumer project
mvn pact:publish \
  -Dpact.broker.url=http://localhost:9292 \
  -Dpact.broker.token=pact_token_secure_2024 \
  -Dpacticipant.version=$(git rev-parse HEAD) \
  -Dpacticipant.tag=develop
```

### Verify Can-I-Deploy

```bash
docker run --rm pactfoundation/pact-cli:latest \
  broker can-i-deploy \
  --pacticipant ms-customer \
  --version $(git rev-parse HEAD) \
  --to-environment production \
  --broker-base-url http://localhost:9292 \
  --broker-token pact_token_secure_2024
```

## Troubleshooting

### Pact Broker Won't Start

**Symptom:** Container exits immediately

**Solutions:**

1. Check PostgreSQL is healthy:
```bash
docker-compose logs postgres-pact
docker exec postgres-pact pg_isready -U fusionx
```

2. Check database connection:
```bash
docker-compose logs pact-broker | grep -i error
```

3. Verify network exists:
```bash
docker network ls | grep eagle-network
```

### Can't Access Web UI

**Symptom:** Browser shows "Connection refused"

**Solutions:**

1. Check Pact Broker is running:
```bash
docker-compose ps pact-broker
```

2. Check port is not in use:
```bash
# Windows
netstat -ano | findstr :9292

# Linux/Mac
lsof -i :9292
```

3. Check health endpoint:
```bash
curl http://localhost:9292/diagnostic/status/heartbeat
```

### Authentication Fails

**Symptom:** 401 Unauthorized

**Solutions:**

1. Verify credentials in `.env` file
2. Check environment variables are loaded:
```bash
docker-compose config | grep PACT_BROKER
```

3. Restart Pact Broker after changing credentials:
```bash
docker-compose restart pact-broker
```

### Database Connection Issues

**Symptom:** "could not connect to server"

**Solutions:**

1. Check PostgreSQL is running:
```bash
docker-compose ps postgres-pact
```

2. Check database exists:
```bash
docker exec postgres-pact psql -U fusionx -l | grep pact_broker
```

3. Recreate database if needed:
```bash
docker-compose down -v
docker-compose up -d
```

### Slow Performance

**Symptom:** Slow response times

**Solutions:**

1. Check PostgreSQL performance:
```bash
docker stats postgres-pact
```

2. Check disk space:
```bash
docker system df
```

3. Clean old data (if needed):
```bash
# Access Pact Broker UI → Settings → Clean
# Or use CLI
docker run --rm pactfoundation/pact-cli:latest \
  broker clean \
  --broker-base-url http://localhost:9292 \
  --broker-token pact_token_secure_2024
```

## Maintenance

### Backup Database

```bash
# Create backup
docker exec postgres-pact pg_dump -U fusionx pact_broker > pact_broker_backup.sql

# Restore backup
docker exec -i postgres-pact psql -U fusionx pact_broker < pact_broker_backup.sql
```

### Update Pact Broker Version

```bash
# 1. Backup database first (see above)

# 2. Update image version in docker-compose.yml
# image: pactfoundation/pact-broker:2.107.1 → 2.108.0

# 3. Pull new image
docker-compose pull pact-broker

# 4. Restart with new version
docker-compose up -d pact-broker

# 5. Verify health
curl http://localhost:9292/diagnostic/status/heartbeat
```

### Clean Old Contracts

```bash
# Remove contracts older than 30 days
docker run --rm pactfoundation/pact-cli:latest \
  broker clean \
  --broker-base-url http://localhost:9292 \
  --broker-token pact_token_secure_2024 \
  --selector-max-age=30
```

### View Logs

```bash
# Pact Broker logs
docker-compose logs -f pact-broker

# PostgreSQL logs
docker-compose logs -f postgres-pact

# Both services
docker-compose logs -f
```

## Integration with Eagle Services

### Consumer Configuration (ms-alert)

```yaml
# src/test/resources/application-contract-test.yml
pact:
  broker:
    url: ${PACT_BROKER_URL:http://localhost:9292}
    token: ${PACT_BROKER_TOKEN}
```

### Provider Configuration (ms-customer)

```java
@Provider("ms-customer")
@PactBroker(
    url = "${pact.broker.url}",
    authentication = @PactBrokerAuth(token = "${pact.broker.token}")
)
class CustomerApiProviderTest {
    // Provider tests
}
```

### CI/CD Integration

```yaml
# .github/workflows/contract-test.yml
env:
  PACT_BROKER_URL: ${{ secrets.PACT_BROKER_URL }}
  PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}
```

## Monitoring

### Metrics Endpoint

```bash
# Prometheus metrics (if enabled)
curl http://localhost:9292/metrics
```

### Key Metrics to Monitor

- Contract verification success rate
- Number of active contracts
- Database connection pool usage
- API response times

## Security Best Practices

1. ✅ Change default passwords in production
2. ✅ Use token authentication for CI/CD
3. ✅ Enable HTTPS in production (use reverse proxy)
4. ✅ Restrict network access (firewall rules)
5. ✅ Regular backups of PostgreSQL database
6. ✅ Monitor for unauthorized access attempts
7. ✅ Keep Pact Broker version updated

## Resources

- [Pact Broker Documentation](https://docs.pact.io/pact_broker)
- [Pact Foundation](https://pact.io/)
- [Eagle Contract Testing Guide](../../docs/contracts/README.md)
- [Contract Matrix](../../docs/contracts/matrix.md)

## Support

- **Team:** Eagle Platform Team
- **Slack:** #eagle-platform
- **Email:** eagle-platform@fusionx.pro
- **Issues:** Create ticket in Jira with label `pact-broker`
