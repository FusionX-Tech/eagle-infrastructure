# Eagle Infrastructure

Esta pasta contém **toda a infraestrutura** do projeto Eagle, seguindo o princípio fundamental de **Separação de Responsabilidades**.

## 🏗️ Estrutura

```
infrastructure/
├── api-gateway/           # Kong API Gateway
├── database/             # PostgreSQL configs
├── keycloak/            # Autenticação e autorização
├── monitoring/          # Prometheus, Grafana, Jaeger
├── vault/               # HashiCorp Vault
├── k8s/                 # Kubernetes manifests
├── istio/               # Service Mesh
├── network/             # Configurações de rede
├── security-tests/      # Testes de segurança
├── docker-compose.yml   # Orquestração principal
└── docker-compose.infra.yml # Infraestrutura isolada
```

## 🚀 Ordem de Inicialização

**OBRIGATÓRIA** - Seguir esta sequência para evitar falhas de dependência:

### 1. Infrastructure Base
```bash
cd Eagle/infrastructure
docker-compose up -d postgres redis
```

### 2. Platform Services  
```bash
docker-compose up -d keycloak kong vault
```

### 3. Monitoring
```bash
docker-compose up -d prometheus grafana jaeger
```

### 4. Applications
```bash
cd ../eagle-backend
docker-compose up -d
```

## 📋 Princípios Aplicados

### ✅ **Separation of Concerns**
- **Infraestrutura** ≠ **Lógica de negócio**
- Cada componente tem responsabilidade clara

### ✅ **Team Independence** 
- DevOps gerencia infra sem afetar desenvolvimento
- Desenvolvedores focam no código das aplicações

### ✅ **Deployment Strategy**
- Infra versionada e deployada independentemente
- Rollbacks isolados por componente

### ✅ **Reusability**
- Configurações reutilizáveis entre projetos
- Templates padronizados

### ✅ **Maintainability**
- Documentação específica por componente
- Health checks e depends_on configurados

## 🔧 Comandos Úteis

### Subir ambiente completo
```bash
cd Eagle/infrastructure
./start-full-environment.sh
```

### Subir apenas infraestrutura
```bash
docker-compose -f docker-compose.infra.yml up -d
```

### Verificar saúde dos serviços
```bash
docker-compose ps
docker-compose logs [service-name]
```

### Parar ambiente
```bash
docker-compose down
```

## 📚 Documentação por Componente

- [API Gateway (Kong)](./api-gateway/README.md)
- [Database (PostgreSQL)](./database/README.md) 
- [Keycloak](./keycloak/README.md)
- [Monitoring](./monitoring/README.md)
- [Vault](./vault/README.md)
- [Kubernetes](./k8s/README.md)

## ⚠️ Regras Importantes

- **NUNCA** colocar configs de infra dentro de `eagle-backend/src/`
- **SEMPRE** documentar mudanças de infraestrutura
- **OBRIGATÓRIO** testar health checks após mudanças
- **PROIBIDO** aplicações conterem configs de outros serviços