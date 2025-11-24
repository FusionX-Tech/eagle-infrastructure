# Neo4j - Graph Database for Eagle

Neo4j Community Edition 5.15 para análise de rede e relacionamentos.

## 🚀 Como Iniciar

```bash
cd Eagle/eagle-infrastructure/neo4j
docker-compose up -d
```

## 🔍 Acessos

- **Neo4j Browser**: http://localhost:7474
- **Bolt Protocol**: bolt://localhost:7687
- **Metrics (Prometheus)**: http://localhost:2004/metrics

### Credenciais Padrão
- **Username**: `neo4j`
- **Password**: `fusionx2024`

## 📊 Verificar Status

```bash
# Ver logs
docker logs fx-neo4j

# Verificar health
curl http://localhost:7474

# Entrar no container
docker exec -it fx-neo4j bash
```

## 🎯 Inicialização

### Constraints e Índices

Os constraints e índices são criados automaticamente pelo ms-graph na primeira sincronização.

Ou você pode executar manualmente:

```bash
# Copiar script para container
docker cp init-scripts/001-create-constraints-and-indexes.cypher fx-neo4j:/tmp/

# Executar script
docker exec fx-neo4j cypher-shell -u neo4j -p fusionx2024 -f /tmp/001-create-constraints-and-indexes.cypher
```

## 📝 Queries Úteis

### Ver todos os nós
```cypher
MATCH (n) RETURN n LIMIT 100
```

### Ver todos os relacionamentos
```cypher
MATCH ()-[r]->() RETURN type(r), count(r)
```

### Ver estatísticas do banco
```cypher
CALL apoc.meta.stats()
```

### Limpar tudo (CUIDADO!)
```cypher
MATCH (n) DETACH DELETE n
```

## 🔧 Configurações

### Memória
- **Heap**: 512MB inicial, 2GB máximo
- **Page Cache**: 1GB
- **Transaction Memory**: 1GB

### Performance
- **Checkpoint Interval**: 15 minutos
- **Connection Pool**: 50 conexões

## 📈 Monitoramento

### Prometheus Metrics

```bash
curl http://localhost:2004/metrics
```

Métricas disponíveis:
- `neo4j_database_system_check_point_duration_time`
- `neo4j_database_transaction_active_count`
- `neo4j_database_pool_total_used`
- `neo4j_database_store_size_total`

### Grafana Dashboard

Importe o dashboard oficial do Neo4j:
- Dashboard ID: 12826

## 🧪 Testes

### Testar Conexão
```bash
docker exec fx-neo4j cypher-shell -u neo4j -p fusionx2024 "RETURN 'Connection OK' as status"
```

### Criar Nó de Teste
```cypher
CREATE (c:Customer {
  id: 'test-123',
  name: 'Test Customer',
  document: '123.456.789-00',
  customerType: 'PERSON',
  status: 'ACTIVE'
})
RETURN c
```

### Buscar Nó de Teste
```cypher
MATCH (c:Customer {id: 'test-123'})
RETURN c
```

### Deletar Nó de Teste
```cypher
MATCH (c:Customer {id: 'test-123'})
DELETE c
```

## 🔒 Segurança

### Alterar Senha

```cypher
ALTER CURRENT USER SET PASSWORD FROM 'fusionx2024' TO 'nova_senha'
```

### Criar Usuário Read-Only

```cypher
CREATE USER analyst SET PASSWORD 'analyst123' CHANGE NOT REQUIRED;
GRANT ROLE reader TO analyst;
```

## 📚 Documentação

- [Neo4j Documentation](https://neo4j.com/docs/)
- [Cypher Manual](https://neo4j.com/docs/cypher-manual/current/)
- [Neo4j Operations Manual](https://neo4j.com/docs/operations-manual/current/)

## 🐛 Troubleshooting

### Container não inicia
```bash
# Ver logs
docker logs fx-neo4j

# Verificar volumes
docker volume ls | grep neo4j

# Remover volumes e reiniciar
docker-compose down -v
docker-compose up -d
```

### Erro de memória
Ajuste as configurações de memória no `docker-compose.yml`:
```yaml
- NEO4J_server_memory_heap_max__size=4G
- NEO4J_server_memory_pagecache_size=2G
```

### Conexão recusada
Verifique se o container está rodando e se as portas estão expostas:
```bash
docker ps | grep neo4j
netstat -an | grep 7474
netstat -an | grep 7687
```
