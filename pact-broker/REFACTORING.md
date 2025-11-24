# Refatoração do Pact Broker - Integração com PostgreSQL Principal

> **⚠️ ATUALIZAÇÃO FINAL (2024-11-15):**  
> O Pact Broker foi **movido para a stack do backend** (`Eagle/eagle-backend/docker-compose.yml`).  
> Agora faz parte do profile `backend` junto com os microsserviços.  
> Documentação completa: [`Eagle/eagle-backend/PACT_BROKER.md`](../../eagle-backend/PACT_BROKER.md)

## Problema Identificado

A implementação inicial do Pact Broker criava um PostgreSQL separado (`postgres-pact` na porta 5436), violando os **princípios de separação de responsabilidades do Eagle**.

## Solução Implementada

Refatoramos a arquitetura para usar o **PostgreSQL do Eagle Backend** (`fx-postgres-eagle`), seguindo as melhores práticas de infraestrutura e colocando o Pact Broker junto com os microsserviços que ele testa.

## Mudanças Realizadas

### 1. Database no PostgreSQL Eagle

**Arquivo**: `Eagle/eagle-backend/local/postgres/initdb-eagle/01_create_databases.sql`

```sql
-- Database para Pact Broker (Contract Testing)
CREATE DATABASE pact_broker;
```

**Justificativa**: O Pact Broker deve estar no mesmo PostgreSQL que os microsserviços que ele testa (fx-postgres-eagle), não no PostgreSQL de infraestrutura (fx-postgres-infra que é para Keycloak, Kong, etc.).

### 2. Docker Compose Refatorado

**Arquivo**: `Eagle/eagle-infrastructure/pact-broker/docker-compose.yml`

**ANTES** (❌ ERRADO):
```yaml
services:
  postgres-pact:  # PostgreSQL separado
    image: postgres:15-alpine
    ports:
      - "5436:5432"
    
  pact-broker:
    depends_on:
      - postgres-pact
    environment:
      PACT_BROKER_DATABASE_URL: postgresql://fusionx:senha@postgres-pact:5432/pact_broker
```

**DEPOIS** (✅ CORRETO):
```yaml
services:
  pact-broker:
    # Usa PostgreSQL Eagle (microsserviços)
    environment:
      PACT_BROKER_DATABASE_URL: postgresql://fusionx:senha@fx-postgres-eagle:5432/pact_broker
    networks:
      - fusionx-eagle-backend_backend-net  # Mesma network dos microsserviços
```

### 3. Variáveis de Ambiente

**Arquivo**: `Eagle/eagle-infrastructure/pact-broker/.env`

```env
# Database (usa PostgreSQL Eagle)
PACT_BROKER_DB_USER=fusionx
PACT_BROKER_DB_PASSWORD=senha

# Autenticação
PACT_BROKER_USERNAME=pact_user
PACT_BROKER_PASSWORD=pact_secure_password_2024
PACT_BROKER_READ_ONLY_USERNAME=pact_reader
PACT_BROKER_READ_ONLY_PASSWORD=pact_reader_password_2024
```

## Arquitetura Final

```
Eagle Infrastructure
├── PostgreSQL Infra (fx-postgres-infra:5432)
│   ├── keycloak          # Database do Keycloak
│   └── kong              # Database do Kong (se usar DB mode)
│
└── Eagle Backend
    ├── PostgreSQL Eagle (fx-postgres-eagle:5435)
    │   ├── ms_customer       # Database do MS Customer
    │   ├── ms_alert          # Database do MS Alert
    │   ├── ms_transaction    # Database do MS Transaction
    │   ├── ms_qa             # Database de QA
    │   ├── ms_rules          # Database do MS Rules
    │   ├── ms_kys            # Database do MS KYS
    │   ├── ms_eagle_flow     # Database do MS Eagle Flow
    │   ├── ms_enrichment     # Database do MS Enrichment
    │   └── pact_broker       # Database do Pact Broker ✅
    │
    └── Pact Broker (fx-pact-broker:9292)
        └── Conecta ao PostgreSQL Eagle
```

## Justificativas Técnicas

### 1. **Separation of Concerns**
- Infraestrutura de dados centralizada
- Um único PostgreSQL para gerenciar

### 2. **Resource Efficiency**
- Elimina duplicação de recursos (memória, CPU)
- Reduz overhead de containers

### 3. **Backup Unificado**
- Uma estratégia de backup para todos os databases
- Simplifica disaster recovery

### 4. **Network Simplicity**
- Menos containers na rede
- Menos pontos de falha

### 5. **Eagle Principles Compliance**
- Segue os princípios do projeto Eagle
- Infraestrutura organizada e centralizada

## Portas Utilizadas

| Serviço | Porta | Propósito |
|---------|-------|-----------|
| PostgreSQL Infra | 5432 | Databases de infraestrutura (Keycloak, Kong) |
| PostgreSQL Eagle | 5435 | Databases dos microsserviços + pact_broker |
| Pact Broker Web UI | 9292 | Interface e API do Pact Broker |

## Verificação do Deployment

### 1. Verificar PostgreSQL Eagle
```bash
docker ps --filter "name=fx-postgres-eagle"
```

### 2. Verificar Database Pact Broker
```bash
docker exec fx-postgres-eagle psql -U fusionx -d pact_broker -c "\dt"
```

### 3. Verificar Pact Broker
```bash
# Health check
curl http://localhost:9292/diagnostic/status/heartbeat

# Web UI
curl -I http://localhost:9292/
```

### 4. Verificar Tabelas Criadas
```bash
docker exec fx-postgres-eagle psql -U fusionx -d pact_broker -c "\dt"
```

Deve listar 30 tabelas do Pact Broker:
- branch_heads
- branch_versions
- branches
- certificates
- config
- deployed_versions
- environments
- integrations
- pact_publications
- pact_versions
- pacticipants
- verifications
- webhooks
- etc.

## Comandos de Gerenciamento

### Iniciar Infraestrutura

**⚠️ ATUALIZAÇÃO: Pact Broker agora faz parte da stack do backend**

```bash
# Opção 1: Iniciar toda a stack do backend (recomendado)
cd Eagle/eagle-backend
docker compose --profile backend up -d

# Opção 2: Apenas PostgreSQL + Pact Broker
cd Eagle/eagle-backend
docker compose --profile backend up -d postgres-eagle pact-broker
```

### Parar Serviços
```bash
# Parar Pact Broker
cd Eagle/eagle-backend
docker compose stop pact-broker

# Parar toda a stack do backend
cd Eagle/eagle-backend
docker compose --profile backend down
```

### Ver Logs
```bash
# Logs do Pact Broker
docker logs fx-pact-broker -f

# Logs do PostgreSQL Eagle
docker logs fx-postgres-eagle -f
```

### Acessar Database
```bash
# Como admin (fusionx)
docker exec -it fx-postgres-eagle psql -U fusionx -d pact_broker

# Listar todos os databases
docker exec -it fx-postgres-eagle psql -U fusionx -d postgres -c "\l"
```

## Troubleshooting

### Problema: Pact Broker não conecta ao PostgreSQL

**Solução**:
```bash
# 1. Verificar se PostgreSQL Eagle está rodando
docker ps --filter "name=fx-postgres-eagle"

# 2. Verificar se estão na mesma network
docker network inspect fusionx-eagle-backend_backend-net

# 3. Testar conexão
docker exec fx-pact-broker ping fx-postgres-eagle
```

### Problema: Erro de permissões no database

**Solução**:
```bash
# Conceder permissões no schema public
docker exec fx-postgres-eagle psql -U fusionx -d pact_broker -c "GRANT ALL ON SCHEMA public TO fusionx;"

# Reiniciar Pact Broker
cd Eagle/eagle-infrastructure/pact-broker
docker compose restart
```

### Problema: Network backend-net não existe

**Solução**:
```bash
# A network é criada automaticamente pelo docker-compose do eagle-backend
# Certifique-se de que o PostgreSQL Eagle está rodando primeiro

cd Eagle/eagle-backend
docker compose --profile backend up -d postgres-eagle

# Depois iniciar Pact Broker
cd ../eagle-infrastructure/pact-broker
docker compose up -d
```

## Benefícios da Refatoração

✅ **Conformidade com Eagle Principles**
✅ **Redução de 1 container (postgres-pact eliminado)**
✅ **Redução de 1 porta (5436 eliminada)**
✅ **Redução de 1 volume (pact-broker-data eliminado)**
✅ **Backup unificado**
✅ **Gerenciamento simplificado**
✅ **Menor consumo de recursos**

## Próximos Passos

1. ✅ Task 1.1: Criar configuração do Pact Broker
2. ✅ Task 1.2: Testar deployment do Pact Broker
3. ⏳ Task 1.3: Criar documentação do Pact Broker

---

**Data da Refatoração**: 2024-11-15
**Responsável**: Kiro AI
**Status**: ✅ Concluído e Testado
