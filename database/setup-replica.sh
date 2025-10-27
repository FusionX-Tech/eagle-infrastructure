#!/bin/bash

# =====================================================
# SCRIPT DE CONFIGURAÇÃO PARA RÉPLICAS POSTGRESQL
# =====================================================

set -e

echo "Configurando réplica PostgreSQL..."

# Aguardar o master estar disponível
until pg_isready -h postgres -p 5432 -U ${POSTGRES_USER}; do
  echo "Aguardando PostgreSQL master..."
  sleep 2
done

# Verificar se já existe dados na réplica
if [ ! -f /var/lib/postgresql/data/PG_VERSION ]; then
    echo "Inicializando réplica com pg_basebackup..."
    
    # Fazer backup base do master
    PGPASSWORD=${POSTGRES_REPLICATION_PASSWORD:-repl_password} pg_basebackup \
        -h postgres \
        -D /var/lib/postgresql/data \
        -U ${POSTGRES_REPLICATION_USER:-replicator} \
        -v -P -W
    
    # Configurar réplica
    cat >> /var/lib/postgresql/data/postgresql.conf << EOF

# Configurações específicas da réplica
hot_standby = on
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 512MB
work_mem = 2MB
maintenance_work_mem = 64MB

# Configurações de replicação
primary_conninfo = 'host=postgres port=5432 user=${POSTGRES_REPLICATION_USER:-replicator} password=${POSTGRES_REPLICATION_PASSWORD:-repl_password}'
primary_slot_name = 'replica_slot_$(hostname)'
hot_standby_feedback = on

# Configurações de logging
log_min_duration_statement = 2000
log_line_prefix = '[REPLICA] %t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Configurações otimizadas para leitura
random_page_cost = 1.0
seq_page_cost = 1.0
cpu_tuple_cost = 0.01
default_statistics_target = 100
EOF

    # Criar arquivo de recovery
    cat > /var/lib/postgresql/data/standby.signal << EOF
# Arquivo que indica que este é um standby server
EOF

    echo "Réplica configurada com sucesso!"
else
    echo "Réplica já configurada, iniciando..."
fi

# Ajustar permissões
chown -R postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

echo "Setup da réplica concluído!"