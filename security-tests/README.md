# Eagle System Security Testing

Este diretório contém uma suite completa de testes de segurança para o sistema Eagle, incluindo testes automatizados de penetração, validação de configurações de segurança e testes de JWT tokens.

## 📋 Componentes de Teste

### 1. SecurityTestSuite.java
**Testes de Segurança Unitários e de Integração**

- **Autenticação JWT**: Validação de tokens válidos, expirados, malformados e inválidos
- **Autorização**: Testes de controle de acesso baseado em roles
- **Validação de Entrada**: Prevenção de SQL Injection, XSS e Command Injection
- **Headers de Segurança**: Verificação de headers obrigatórios (X-Frame-Options, CSP, etc.)
- **Rate Limiting**: Testes de limitação de taxa de requisições
- **Endpoints Sensíveis**: Proteção de endpoints do Actuator
- **CORS**: Configuração adequada de Cross-Origin Resource Sharing
- **Auditoria**: Logging de operações sensíveis

### 2. penetration-tests.py
**Testes de Penetração Automatizados**

- **Testes de Autenticação**: Bypass de autenticação, tokens malformados
- **Testes de Autorização**: Escalação de privilégios, acesso não autorizado
- **Testes de Injeção**: SQL Injection, XSS, Command Injection
- **Vazamento de Informações**: Exposição de dados sensíveis
- **Configuração SSL/TLS**: Validação de certificados e redirecionamentos
- **Rate Limiting**: Testes de DoS e limitação de taxa

### 3. security-config-validator.sh
**Validador de Configurações de Segurança**

- **Microserviços**: Verificação de configurações Spring Security
- **Infraestrutura**: PostgreSQL, Redis, Kong, Keycloak, Vault
- **Rede Docker**: Isolamento e configurações de rede
- **Headers de Segurança**: Validação automática de headers
- **Logging de Segurança**: Verificação de logs de auditoria

## 🚀 Como Executar os Testes

### Pré-requisitos

```bash
# Instalar dependências Python
pip install requests pyjwt

# Instalar jq para parsing JSON (Linux/Mac)
# Ubuntu/Debian: sudo apt-get install jq
# CentOS/RHEL: sudo yum install jq
# macOS: brew install jq

# Verificar se Docker está rodando
docker --version
```

### 1. Executar Testes Unitários de Segurança

```bash
# No diretório do microserviço (ex: ms-alert)
cd services/ms-alert

# Executar testes de segurança
mvn test -Dtest=SecurityTestSuite

# Ou executar todos os testes incluindo segurança
mvn test
```

### 2. Executar Testes de Penetração

```bash
# Subir o ambiente completo
docker-compose up -d

# Aguardar todos os serviços ficarem prontos
sleep 60

# Executar testes sem autenticação (testa proteções básicas)
python infra/security-tests/penetration-tests.py --target http://localhost:8080

# Executar testes com token JWT (testa funcionalidades autenticadas)
# Primeiro, obter um token do Keycloak
TOKEN=$(curl -s -X POST "http://localhost:8081/realms/eagle-dev/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=eagle-services" \
  -d "client_secret=your-client-secret" | jq -r '.access_token')

# Executar testes com token
python infra/security-tests/penetration-tests.py --target http://localhost:8080 --token "$TOKEN"
```

### 3. Validar Configurações de Segurança

```bash
# Executar validador de configurações (Linux/Mac)
bash infra/security-tests/security-config-validator.sh

# No Windows, executar manualmente as verificações ou usar WSL
```

## 🔍 Interpretando os Resultados

### Códigos de Status

- **PASS** ✅: Teste passou, configuração segura
- **FAIL** ❌: Vulnerabilidade crítica encontrada
- **WARN** ⚠️: Possível problema de segurança, requer atenção
- **INFO** ℹ️: Informação sobre configuração

### Relatórios Gerados

Os testes geram relatórios detalhados:

```
security_report_YYYYMMDD_HHMMSS.json  # Relatório detalhado em JSON
security_validation_report.txt        # Relatório de validação de configurações
```

## 🛡️ Checklist de Segurança

### Autenticação e Autorização
- [ ] JWT tokens são validados corretamente
- [ ] Tokens expirados são rejeitados
- [ ] Tokens malformados são rejeitados
- [ ] Roles são verificadas para cada endpoint
- [ ] Endpoints sensíveis estão protegidos

### Validação de Entrada
- [ ] SQL Injection é prevenida
- [ ] XSS é prevenida
- [ ] Command Injection é prevenida
- [ ] Validação de tamanho de payload
- [ ] Sanitização de dados de entrada

### Headers de Segurança
- [ ] X-Content-Type-Options: nosniff
- [ ] X-Frame-Options: DENY ou SAMEORIGIN
- [ ] X-XSS-Protection: 1; mode=block
- [ ] Strict-Transport-Security (HTTPS)
- [ ] Content-Security-Policy configurada

### Configuração de Infraestrutura
- [ ] PostgreSQL não exposto externamente
- [ ] Redis com autenticação habilitada
- [ ] Keycloak com configurações seguras
- [ ] Kong com plugins de segurança
- [ ] Vault selado e inicializado

### Rede e Comunicação
- [ ] Containers em rede privada
- [ ] HTTPS configurado (produção)
- [ ] CORS configurado adequadamente
- [ ] Rate limiting ativo

### Logging e Monitoramento
- [ ] Logs de segurança habilitados
- [ ] Tentativas de acesso não autorizado logadas
- [ ] Operações sensíveis auditadas
- [ ] Alertas de segurança configurados

## 🔧 Configurações de Segurança Recomendadas

### application.yml (Microserviços)

```yaml
# Configurações de segurança
server:
  error:
    include-stacktrace: never
    include-message: never
  max-http-header-size: 8KB

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/eagle-dev
          jwk-set-uri: http://keycloak:8080/realms/eagle-dev/protocol/openid-connect/certs

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
        exclude: env,configprops,beans,heapdump,threaddump
  endpoint:
    health:
      show-details: when-authorized
      roles: ADMIN

logging:
  level:
    org.springframework.security: INFO
    org.springframework.web.filter.CommonsRequestLoggingFilter: DEBUG
```

### Configuração Kong (kong.yml)

```yaml
_format_version: "3.0"

services:
- name: eagle-services
  url: http://ms-orchestrator:8088
  plugins:
  - name: rate-limiting
    config:
      minute: 100
      hour: 1000
  - name: jwt
    config:
      key_claim_name: iss
  - name: cors
    config:
      origins:
      - "http://localhost:3000"
      - "https://eagle.company.com"
      methods:
      - GET
      - POST
      - PUT
      - DELETE
      headers:
      - Accept
      - Authorization
      - Content-Type
      exposed_headers:
      - X-Auth-Token
      credentials: true
      max_age: 3600
```

### Configuração PostgreSQL

```bash
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
password_encryption = scram-sha-256
log_connections = on
log_disconnections = on
log_statement = 'mod'
```

### Configuração Redis

```bash
# redis.conf
requirepass your-strong-password
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG "CONFIG_b840fc02d524045429941cc15f59e41cb7be6c52"
bind 127.0.0.1
protected-mode yes
```

## 🚨 Vulnerabilidades Comuns e Mitigações

### 1. JWT Token Vulnerabilities
**Problema**: Tokens sem validação adequada
**Mitigação**: 
- Validar assinatura, expiração e issuer
- Usar algoritmos seguros (RS256)
- Implementar blacklist para tokens revogados

### 2. SQL Injection
**Problema**: Queries dinâmicas sem sanitização
**Mitigação**:
- Usar PreparedStatements
- Validar entrada com Bean Validation
- Implementar whitelist de caracteres permitidos

### 3. XSS (Cross-Site Scripting)
**Problema**: Dados não sanitizados no frontend
**Mitigação**:
- Escapar dados de saída
- Usar Content Security Policy
- Validar entrada no backend

### 4. Insecure Direct Object References
**Problema**: Acesso direto a recursos sem autorização
**Mitigação**:
- Implementar controle de acesso por recurso
- Usar UUIDs em vez de IDs sequenciais
- Validar propriedade do recurso

### 5. Security Misconfiguration
**Problema**: Configurações padrão inseguras
**Mitigação**:
- Desabilitar endpoints desnecessários
- Configurar headers de segurança
- Usar HTTPS em produção

## 📊 Métricas de Segurança

### Métricas para Monitoramento

```promql
# Taxa de tentativas de autenticação falhadas
sum(rate(http_server_requests_seconds_count{status="401"}[5m]))

# Taxa de tentativas de autorização negadas
sum(rate(http_server_requests_seconds_count{status="403"}[5m]))

# Tentativas de acesso a endpoints sensíveis
sum(rate(http_server_requests_seconds_count{uri=~"/actuator/(env|configprops|beans)"}[5m]))

# Rate limiting ativo
sum(rate(http_server_requests_seconds_count{status="429"}[5m]))
```

### Alertas de Segurança

```yaml
# prometheus/rules/security-alerts.yml
groups:
- name: security-alerts
  rules:
  - alert: HighAuthenticationFailureRate
    expr: sum(rate(http_server_requests_seconds_count{status="401"}[5m])) > 10
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High authentication failure rate detected"
      
  - alert: SensitiveEndpointAccess
    expr: sum(rate(http_server_requests_seconds_count{uri=~"/actuator/(env|configprops|beans)"}[5m])) > 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Access to sensitive endpoint detected"
```

## 🔄 Integração com CI/CD

### GitHub Actions

```yaml
name: Security Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  security-tests:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up JDK 17
      uses: actions/setup-java@v3
      with:
        java-version: '17'
        distribution: 'temurin'
    
    - name: Run Security Unit Tests
      run: mvn test -Dtest=SecurityTestSuite
    
    - name: Start Services
      run: docker-compose up -d
    
    - name: Wait for Services
      run: sleep 60
    
    - name: Run Penetration Tests
      run: |
        pip install requests pyjwt
        python infra/security-tests/penetration-tests.py --target http://localhost:8080
    
    - name: Validate Security Configuration
      run: bash infra/security-tests/security-config-validator.sh
    
    - name: Upload Security Report
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: security-report
        path: security_report_*.json
```

## 📚 Referências

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- [Spring Security Reference](https://docs.spring.io/spring-security/reference/)
- [JWT Security Best Practices](https://tools.ietf.org/html/rfc8725)
- [Docker Security](https://docs.docker.com/engine/security/)
- [Kong Security](https://docs.konghq.com/hub/?category=security)

## 🆘 Suporte

Para questões sobre segurança:
1. Revisar este documento
2. Executar os testes automatizados
3. Consultar logs de segurança
4. Contatar a equipe de segurança