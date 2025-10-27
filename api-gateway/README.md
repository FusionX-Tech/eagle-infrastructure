# Kong API Gateway - Eagle Alert System

Este diretório contém a configuração completa do Kong API Gateway para o Sistema de Criação de Alertas Eagle, incluindo autenticação, autorização, rate limiting, políticas de segurança e monitoramento.

## 📋 Visão Geral

O Kong API Gateway atua como ponto de entrada único para todos os microserviços do sistema, fornecendo:

- **Autenticação JWT** integrada com Keycloak
- **Rate Limiting** por cliente e endpoint
- **Políticas de Segurança** (CORS, CSP, Headers de Segurança)
- **Monitoramento e Logging** para auditoria
- **Validação de Requisições** e sanitização
- **Proteção contra Bots** e ataques automatizados

## 🏗️ Arquitetura

```
Frontend/Mobile → Kong Gateway → Microserviços
                      ↓
                 Keycloak (JWT)
                      ↓
                 Redis (Cache/Rate Limiting)
                      ↓
                 Monitoring/Logging
```

## 📁 Estrutura de Arquivos

```
infra/api-gateway/
├── kong.yml                    # Configuração principal do Kong
├── kong-security-policies.yml  # Políticas de segurança avançadas
├── security-headers.yml        # Headers de segurança (CSP, HSTS, etc.)
├── cors-config.yml             # Configuração CORS detalhada
├── security-monitoring.yml     # Monitoramento e detecção de ameaças
├── csp-config.lua              # Plugin customizado para CSP
├── setup-gateway.sh            # Script de configuração inicial
├── keycloak-integration.sh     # Integração com Keycloak
├── validate-security.sh        # Validação de segurança
└── README.md                   # Esta documentação
```

## 🚀 Configuração e Deploy

### 1. Pré-requisitos

- Docker e Docker Compose
- Keycloak configurado e rodando
- Redis cluster ativo
- Microserviços deployados

### 2. Inicialização

```bash
# 1. Subir o Kong via Docker Compose
docker-compose up -d kong

# 2. Aguardar Kong estar pronto
docker-compose logs -f kong

# 3. Configurar integração com Keycloak
./infra/api-gateway/setup-gateway.sh

# 4. Validar configuração de segurança
./infra/api-gateway/validate-security.sh
```

### 3. Verificação

```bash
# Status do Kong
curl http://localhost:8001/status

# Rotas configuradas
curl http://localhost:8001/routes

# Consumidores
curl http://localhost:8001/consumers

# Plugins ativos
curl http://localhost:8001/plugins
```

## 🔐 Configuração de Segurança

### Autenticação JWT

- **Issuer**: `http://keycloak:8080/realms/eagle-dev`
- **Algorithm**: RS256
- **Public Key**: Obtida automaticamente do Keycloak
- **Consumers**: `eagle-frontend`, `eagle-mobile`

### Rate Limiting

| Endpoint | Por Minuto | Por Hora | Por Dia |
|----------|------------|----------|---------|
| `/api/v1/alerts` (POST) | 50 | 500 | 5,000 |
| `/api/v1/alerts/status` (GET) | 200 | 2,000 | 20,000 |
| Outros endpoints | 100 | 1,000 | 10,000 |

### Headers de Segurança

- **Content-Security-Policy**: Proteção contra XSS
- **X-Frame-Options**: Proteção contra clickjacking
- **X-Content-Type-Options**: Prevenção de MIME sniffing
- **Strict-Transport-Security**: Força HTTPS
- **Referrer-Policy**: Controla informações de referrer

### CORS

- **Origens Permitidas**: 
  - `http://localhost:3000` (desenvolvimento)
  - `https://eagle.fusionx.com.br` (produção)
- **Métodos**: GET, POST, PUT, DELETE, OPTIONS
- **Headers**: Authorization, Content-Type, X-Request-ID
- **Credentials**: Permitido para origens autorizadas

## 🛡️ Recursos de Segurança

### 1. Detecção de Ameaças

- **SQL Injection**: Padrões maliciosos em queries
- **XSS**: Scripts maliciosos em parâmetros
- **Path Traversal**: Tentativas de acesso a arquivos
- **User-Agent Suspeito**: Ferramentas de scanning

### 2. Proteção contra Bots

- **User-Agents Bloqueados**: curl, wget, sqlmap, nikto, etc.
- **Rate Limiting Agressivo**: Para requisições automatizadas
- **Captcha Integration**: Para casos suspeitos (futuro)

### 3. Validação de Requisições

- **Schema Validation**: JSON Schema para payloads
- **Size Limiting**: Máximo 10MB por requisição
- **Content-Type**: Apenas tipos permitidos

### 4. Monitoramento e Auditoria

- **Logs Estruturados**: JSON com contexto completo
- **Métricas Prometheus**: Performance e segurança
- **Alertas em Tempo Real**: Para eventos críticos
- **Audit Trail**: Rastreabilidade completa

## 🔧 Configuração por Ambiente

### Desenvolvimento

```yaml
# Configurações mais permissivas para desenvolvimento
cors:
  origins: ["http://localhost:*"]
rate_limiting:
  minute: 1000  # Mais permissivo
logging:
  level: debug
```

### Produção

```yaml
# Configurações restritivas para produção
cors:
  origins: ["https://eagle.fusionx.com.br"]
rate_limiting:
  minute: 100   # Mais restritivo
logging:
  level: warn
ssl:
  enabled: true
  redirect: true
```

## 📊 Monitoramento

### Métricas Disponíveis

- **Request Rate**: Requisições por segundo
- **Response Time**: Latência por endpoint
- **Error Rate**: Taxa de erros por serviço
- **Security Events**: Tentativas de ataque detectadas

### Dashboards

- **Kong Admin**: http://localhost:8001
- **Prometheus Metrics**: http://localhost:8080/metrics
- **Security Dashboard**: http://localhost:8080/security/dashboard

### Alertas

- **High Error Rate**: > 5% em 5 minutos
- **Security Threat**: Detecção imediata
- **Rate Limit Exceeded**: Por consumidor
- **Service Down**: Health check failure

## 🔍 Troubleshooting

### Problemas Comuns

1. **JWT Token Inválido**
   ```bash
   # Verificar configuração do Keycloak
   curl http://keycloak:8080/realms/eagle-dev/.well-known/openid_configuration
   
   # Reconfigurar JWT no Kong
   ./infra/api-gateway/setup-gateway.sh
   ```

2. **CORS Errors**
   ```bash
   # Verificar configuração CORS
   curl -I -X OPTIONS -H "Origin: https://eagle.fusionx.com.br" \
        http://localhost:8080/api/v1/alerts
   ```

3. **Rate Limiting Issues**
   ```bash
   # Verificar Redis connection
   docker-compose exec redis-master redis-cli ping
   
   # Verificar configuração rate limiting
   curl http://localhost:8001/plugins | jq '.data[] | select(.name=="rate-limiting")'
   ```

4. **Security Headers Missing**
   ```bash
   # Executar validação de segurança
   ./infra/api-gateway/validate-security.sh
   ```

### Logs Úteis

```bash
# Logs do Kong
docker-compose logs -f kong

# Logs de segurança
docker-compose exec kong tail -f /tmp/security-audit.log

# Logs de acesso
docker-compose exec kong tail -f /tmp/access.log
```

## 🔄 Atualizações e Manutenção

### Rotação de Chaves

```bash
# Atualizar chave pública do Keycloak
./infra/api-gateway/keycloak-integration.sh

# Verificar configuração
curl http://localhost:8001/consumers/eagle-frontend/jwt
```

### Atualização de Políticas

```bash
# Aplicar novas configurações
docker-compose restart kong

# Validar mudanças
./infra/api-gateway/validate-security.sh
```

### Backup de Configuração

```bash
# Exportar configuração atual
curl http://localhost:8001/config > kong-backup-$(date +%Y%m%d).json

# Restaurar configuração
curl -X POST http://localhost:8001/config -d @kong-backup.json
```

## 📚 Referências

- [Kong Documentation](https://docs.konghq.com/)
- [Kong Security Best Practices](https://docs.konghq.com/gateway/latest/production/security/)
- [Keycloak Integration](https://docs.konghq.com/hub/kong-inc/openid-connect/)
- [OWASP API Security](https://owasp.org/www-project-api-security/)

## 🤝 Suporte

Para questões relacionadas ao API Gateway:

1. Verificar logs: `docker-compose logs kong`
2. Executar validação: `./validate-security.sh`
3. Consultar documentação do Kong
4. Contatar equipe de DevSecOps