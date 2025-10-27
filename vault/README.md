# HashiCorp Vault Integration

Este documento descreve a integração do HashiCorp Vault no sistema Eagle para gerenciamento seguro de secrets e rotação automática de credenciais.

## 📋 Visão Geral

O Vault fornece:
- **Gerenciamento Centralizado de Secrets**: Todas as credenciais são armazenadas de forma segura
- **Credenciais Dinâmicas**: Geração automática de credenciais de banco com TTL limitado
- **Rotação Automática**: Renovação automática de credenciais antes da expiração
- **Auditoria Completa**: Log de todos os acessos a secrets
- **Controle de Acesso**: Políticas granulares por microserviço

## 🚀 Configuração Inicial

### 1. Inicializar Vault

```bash
# Subir o Vault
docker-compose up -d vault

# Aguardar inicialização
docker logs -f fx-vault

# Verificar status
docker exec fx-vault vault status
```

### 2. Configurar Credenciais nos Microserviços

```bash
# Executar script de configuração
chmod +x infra/vault/update-env-files.sh
./infra/vault/update-env-files.sh

# Para ambiente de desenvolvimento (habilita endpoints de management)
./infra/vault/update-env-files.sh --enable-management
```

### 3. Reiniciar Microserviços

```bash
docker-compose restart ms-alert ms-customer ms-transaction ms-api ms-enrichment ms-orchestrator
```

## 🔐 Estrutura de Secrets

### Secrets Estáticos (KV Store)

```
secret/
├── microservices/
│   ├── database/          # Configurações de banco
│   ├── keycloak/          # Configurações Keycloak
│   └── vault-auth/        # Credenciais AppRole
├── redis/
│   └── cluster/           # Configurações Redis
├── aws/
│   └── credentials/       # Credenciais AWS/LocalStack
├── external-apis/
│   └── portal-transparencia/  # APIs externas
└── jwt/
    └── signing/           # Chaves JWT
```

### Secrets Dinâmicos (Database Engine)

```
database/
├── config/
│   └── postgresql/        # Configuração do banco
└── creds/
    ├── eagle-db-role/     # Credenciais read-write
    └── eagle-readonly-role/  # Credenciais read-only
```

## 🔧 Uso nos Microserviços

### 1. Configuração Spring Boot

Adicione ao `application.yml`:

```yaml
# Incluir configuração do Vault
spring:
  config:
    import: classpath:vault-application.yml
```

### 2. Injeção de Dependências

```java
@Service
@RequiredArgsConstructor
public class MyService {
    
    private final VaultSecretService vaultSecretService;
    
    public void useSecrets() {
        // Obter credenciais de banco
        DatabaseCredentials dbCreds = vaultSecretService.getDatabaseCredentials();
        
        // Obter credenciais dinâmicas
        DynamicDatabaseCredentials dynCreds = 
            vaultSecretService.getDynamicDatabaseCredentials("eagle-db-role");
        
        // Obter secrets específicos
        String apiKey = vaultSecretService.getSecret("external-apis/portal-transparencia", "api_key")
            .orElse("default-key");
    }
}
```

### 3. Configuração de DataSource com Vault

```java
@Configuration
public class DatabaseConfig {
    
    @Bean
    @Primary
    @ConditionalOnProperty(name = "vault.database.dynamic-credentials.enabled", havingValue = "true")
    public DataSource vaultDataSource(VaultSecretService vaultService) {
        // Configuração automática com credenciais dinâmicas
        return new VaultDatabaseConfig(vaultService).vaultDataSource();
    }
}
```

## 🔄 Rotação Automática de Credenciais

### Configuração

A rotação é configurada automaticamente:

- **Intervalo de Verificação**: 30 minutos
- **Threshold de Renovação**: 75% do tempo de lease
- **TTL Padrão**: 1 hora (configurável)
- **TTL Máximo**: 24 horas

### Monitoramento

```bash
# Verificar status das credenciais
curl -H "Authorization: Bearer <token>" \
  http://localhost:8083/api/v1/vault/database/credentials/info

# Forçar rotação manual
curl -X POST -H "Authorization: Bearer <token>" \
  http://localhost:8083/api/v1/vault/database/credentials/rotate
```

## 🏥 Health Checks

### Verificar Status do Vault

```bash
# Via Docker
docker exec fx-vault vault status

# Via API
curl http://localhost:8200/v1/sys/health

# Via Spring Actuator
curl http://localhost:8083/actuator/health/vault
```

### Métricas Disponíveis

- **vault.health**: Status geral do Vault
- **vault.database.credentials.rotation**: Última rotação de credenciais
- **vault.secrets.access**: Acessos a secrets por microserviço

## 🛠️ Operações Administrativas

### Acessar UI do Vault

```
URL: http://localhost:8200
Token: myroot (desenvolvimento)
```

### Comandos Úteis

```bash
# Listar secrets
docker exec fx-vault vault kv list secret/microservices/

# Ler secret específico
docker exec fx-vault vault kv get secret/microservices/database

# Criar novo secret
docker exec fx-vault vault kv put secret/microservices/new-service \
  username=user password=pass

# Gerar credenciais dinâmicas
docker exec fx-vault vault read database/creds/eagle-db-role

# Verificar políticas
docker exec fx-vault vault policy list
docker exec fx-vault vault policy read microservices-policy
```

### Backup e Restore

```bash
# Backup (desenvolvimento)
docker exec fx-vault vault operator raft snapshot save /vault/data/backup.snap

# Restore
docker exec fx-vault vault operator raft snapshot restore /vault/data/backup.snap
```

## 🔒 Segurança

### Políticas de Acesso

- **microservices-policy**: Acesso limitado aos secrets necessários
- **admin-policy**: Acesso completo para administração

### Auditoria

Logs de auditoria são salvos em `/vault/logs/audit.log`:

```bash
# Visualizar logs de auditoria
docker exec fx-vault tail -f /vault/logs/audit.log
```

### Rotação de Tokens

```bash
# Renovar token AppRole
docker exec fx-vault vault write auth/approle/role/microservices-role/secret-id

# Atualizar credenciais nos microserviços
./infra/vault/update-env-files.sh
```

## 🚨 Troubleshooting

### Problemas Comuns

1. **Vault Sealed**
   ```bash
   docker exec fx-vault vault operator unseal
   ```

2. **Credenciais Expiradas**
   ```bash
   # Verificar TTL
   docker exec fx-vault vault read database/creds/eagle-db-role
   
   # Forçar rotação
   curl -X POST http://localhost:8083/api/v1/vault/database/credentials/rotate
   ```

3. **Conectividade**
   ```bash
   # Testar conectividade
   curl http://localhost:8083/api/v1/vault/health
   ```

### Logs Úteis

```bash
# Logs do Vault
docker logs fx-vault

# Logs dos microserviços (filtrar por Vault)
docker logs fx-ms-alert | grep -i vault

# Health checks
curl http://localhost:8083/actuator/health | jq '.components.vault'
```

## 📊 Monitoramento em Produção

### Métricas Importantes

- Taxa de rotação de credenciais
- Tempo de resposta do Vault
- Falhas de autenticação
- Uso de TTL por secret

### Alertas Recomendados

- Vault indisponível por > 1 minuto
- Falha na rotação de credenciais
- TTL de credenciais < 10% do tempo total
- Tentativas de acesso negado > threshold

## 🔄 Migração de Secrets Existentes

Para migrar secrets existentes para o Vault:

1. **Identificar secrets atuais** nos arquivos `.env`
2. **Criar secrets no Vault** usando a CLI ou UI
3. **Atualizar código** para usar `VaultSecretService`
4. **Remover secrets** dos arquivos de configuração
5. **Testar** a aplicação com os novos secrets

### Script de Migração

```bash
# Executar migração automática
./infra/vault/migrate-secrets.sh
```

## 📚 Referências

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Spring Vault Reference](https://docs.spring.io/spring-vault/docs/current/reference/html/)
- [Vault Best Practices](https://learn.hashicorp.com/tutorials/vault/production-hardening)