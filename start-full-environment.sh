#!/bin/bash

# Eagle Infrastructure Startup Script
# Segue a ordem obrigatória de inicialização definida nos princípios

set -e

echo "🚀 Iniciando Eagle Infrastructure..."
echo "📋 Seguindo ordem obrigatória de dependências"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para aguardar serviço ficar saudável
wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}⏳ Aguardando $service ficar disponível...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps $service | grep -q "Up"; then
            if nc -z localhost $port 2>/dev/null; then
                echo -e "${GREEN}✅ $service está disponível!${NC}"
                return 0
            fi
        fi
        
        echo -e "${YELLOW}   Tentativa $attempt/$max_attempts...${NC}"
        sleep 5
        ((attempt++))
    done
    
    echo -e "${RED}❌ $service não ficou disponível após $max_attempts tentativas${NC}"
    return 1
}

# 1. Infrastructure Base
echo -e "\n${BLUE}📦 1. Iniciando Infrastructure Base (PostgreSQL, Redis)${NC}"
docker-compose up -d postgres redis

wait_for_service "postgres" 5432
wait_for_service "redis" 6379

# 2. Platform Services
echo -e "\n${BLUE}🔐 2. Iniciando Platform Services (Keycloak, Kong, Vault)${NC}"
docker-compose up -d keycloak kong vault

wait_for_service "keycloak" 8080
wait_for_service "kong" 8000
wait_for_service "vault" 8200

# 3. Monitoring
echo -e "\n${BLUE}📊 3. Iniciando Monitoring (Prometheus, Grafana, Jaeger)${NC}"
docker-compose up -d prometheus grafana jaeger

wait_for_service "prometheus" 9090
wait_for_service "grafana" 3000
wait_for_service "jaeger" 16686

# 4. Verificação final
echo -e "\n${BLUE}🔍 4. Verificação Final${NC}"
echo -e "${GREEN}✅ Infraestrutura iniciada com sucesso!${NC}"

echo -e "\n${BLUE}📋 Serviços Disponíveis:${NC}"
echo -e "  🗄️  PostgreSQL:  localhost:5432"
echo -e "  🔴 Redis:        localhost:6379"
echo -e "  🔐 Keycloak:     http://localhost:8080"
echo -e "  🌐 Kong:         http://localhost:8000"
echo -e "  🔒 Vault:        http://localhost:8200"
echo -e "  📊 Prometheus:   http://localhost:9090"
echo -e "  📈 Grafana:      http://localhost:3000"
echo -e "  🔍 Jaeger:       http://localhost:16686"

echo -e "\n${YELLOW}📝 Próximos passos:${NC}"
echo -e "  1. Configurar Keycloak: cd keycloak && ./scripts/setup-keycloak.ps1"
echo -e "  2. Iniciar aplicações: cd ../eagle-backend && docker-compose up -d"

echo -e "\n${GREEN}🎉 Eagle Infrastructure está pronta!${NC}"