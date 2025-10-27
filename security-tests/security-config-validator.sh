#!/bin/bash

# Security Configuration Validator for Eagle System
# Valida configurações de segurança em todos os microserviços

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Contadores
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Função para logging
log_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local severity="$4"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    case $severity in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $test_name: $status"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $test_name: $status"
            echo -e "       $details"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $test_name: $status"
            echo -e "       $details"
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            ;;
        *)
            echo -e "${BLUE}[INFO]${NC} $test_name: $status"
            ;;
    esac
}

# Função para verificar se um serviço está rodando
check_service_running() {
    local service_name="$1"
    local port="$2"
    
    if curl -s -f "http://localhost:$port/actuator/health" > /dev/null 2>&1; then
        log_result "Service $service_name" "Running" "Service is accessible on port $port" "PASS"
        return 0
    else
        log_result "Service $service_name" "Not Running" "Service not accessible on port $port" "FAIL"
        return 1
    fi
}

# Função para verificar configurações de segurança do Spring Boot
check_spring_security_config() {
    local service_name="$1"
    local port="$2"
    
    echo -e "\n${BLUE}=== Checking Spring Security Configuration for $service_name ===${NC}"
    
    # Verificar se endpoints sensíveis estão protegidos
    local sensitive_endpoints=(
        "/actuator/env"
        "/actuator/configprops"
        "/actuator/beans"
        "/actuator/heapdump"
        "/actuator/threaddump"
    )
    
    for endpoint in "${sensitive_endpoints[@]}"; do
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$endpoint")
        
        if [[ "$response_code" == "401" || "$response_code" == "403" ]]; then
            log_result "$service_name Endpoint $endpoint" "Protected" "Returns $response_code" "PASS"
        elif [[ "$response_code" == "404" ]]; then
            log_result "$service_name Endpoint $endpoint" "Not Found" "Endpoint disabled" "PASS"
        else
            log_result "$service_name Endpoint $endpoint" "Exposed" "Returns $response_code - should be protected" "FAIL"
        fi
    done
    
    # Verificar se endpoints públicos estão acessíveis
    local public_endpoints=(
        "/actuator/health"
        "/actuator/info"
    )
    
    for endpoint in "${public_endpoints[@]}"; do
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$endpoint")
        
        if [[ "$response_code" == "200" ]]; then
            log_result "$service_name Public Endpoint $endpoint" "Accessible" "Returns $response_code" "PASS"
        else
            log_result "$service_name Public Endpoint $endpoint" "Not Accessible" "Returns $response_code - should be public" "WARN"
        fi
    done
}

# Função para verificar headers de segurança
check_security_headers() {
    local service_name="$1"
    local port="$2"
    
    echo -e "\n${BLUE}=== Checking Security Headers for $service_name ===${NC}"
    
    local headers_response=$(curl -s -I "http://localhost:$port/actuator/health")
    
    # Headers obrigatórios
    local required_headers=(
        "X-Content-Type-Options"
        "X-Frame-Options"
        "X-XSS-Protection"
    )
    
    for header in "${required_headers[@]}"; do
        if echo "$headers_response" | grep -qi "$header"; then
            local header_value=$(echo "$headers_response" | grep -i "$header" | cut -d: -f2- | tr -d '\r\n' | xargs)
            log_result "$service_name Header $header" "Present" "Value: $header_value" "PASS"
        else
            log_result "$service_name Header $header" "Missing" "Security header not found" "FAIL"
        fi
    done
    
    # Headers recomendados
    local recommended_headers=(
        "Strict-Transport-Security"
        "Content-Security-Policy"
        "Referrer-Policy"
    )
    
    for header in "${recommended_headers[@]}"; do
        if echo "$headers_response" | grep -qi "$header"; then
            local header_value=$(echo "$headers_response" | grep -i "$header" | cut -d: -f2- | tr -d '\r\n' | xargs)
            log_result "$service_name Header $header" "Present" "Value: $header_value" "PASS"
        else
            log_result "$service_name Header $header" "Missing" "Recommended security header not found" "WARN"
        fi
    done
}

# Função para verificar configurações do Keycloak
check_keycloak_security() {
    echo -e "\n${BLUE}=== Checking Keycloak Security Configuration ===${NC}"
    
    # Verificar se Keycloak está rodando
    if ! check_service_running "Keycloak" "8081"; then
        return 1
    fi
    
    # Verificar configurações do realm
    local keycloak_info=$(curl -s "http://localhost:8081/realms/eagle-dev/.well-known/openid_configuration" 2>/dev/null)
    
    if [[ -n "$keycloak_info" ]]; then
        log_result "Keycloak Realm" "Accessible" "eagle-dev realm is configured" "PASS"
        
        # Verificar algoritmos de assinatura
        local algorithms=$(echo "$keycloak_info" | jq -r '.id_token_signing_alg_values_supported[]' 2>/dev/null)
        if echo "$algorithms" | grep -q "RS256"; then
            log_result "Keycloak JWT Algorithm" "Secure" "RS256 algorithm supported" "PASS"
        else
            log_result "Keycloak JWT Algorithm" "Insecure" "RS256 algorithm not found" "WARN"
        fi
    else
        log_result "Keycloak Realm" "Not Accessible" "Cannot access realm configuration" "FAIL"
    fi
}

# Função para verificar configurações do PostgreSQL
check_postgresql_security() {
    echo -e "\n${BLUE}=== Checking PostgreSQL Security Configuration ===${NC}"
    
    # Verificar se PostgreSQL está rodando
    if docker ps | grep -q "fx-postgres-master"; then
        log_result "PostgreSQL Master" "Running" "Container is active" "PASS"
    else
        log_result "PostgreSQL Master" "Not Running" "Container not found" "FAIL"
        return 1
    fi
    
    # Verificar configurações de rede
    local pg_networks=$(docker inspect fx-postgres-master | jq -r '.[0].NetworkSettings.Networks | keys[]' 2>/dev/null)
    if echo "$pg_networks" | grep -q "fusionx-net"; then
        log_result "PostgreSQL Network" "Isolated" "Running on private network" "PASS"
    else
        log_result "PostgreSQL Network" "Exposed" "Not running on private network" "WARN"
    fi
    
    # Verificar se portas estão expostas apenas localmente
    local pg_ports=$(docker port fx-postgres-master 2>/dev/null)
    if echo "$pg_ports" | grep -q "127.0.0.1"; then
        log_result "PostgreSQL Port Binding" "Secure" "Bound to localhost only" "PASS"
    elif echo "$pg_ports" | grep -q "0.0.0.0"; then
        log_result "PostgreSQL Port Binding" "Insecure" "Bound to all interfaces" "FAIL"
    else
        log_result "PostgreSQL Port Binding" "Unknown" "Cannot determine port binding" "WARN"
    fi
}

# Função para verificar configurações do Redis
check_redis_security() {
    echo -e "\n${BLUE}=== Checking Redis Security Configuration ===${NC}"
    
    # Verificar se Redis está rodando
    if docker ps | grep -q "fx-redis-master"; then
        log_result "Redis Master" "Running" "Container is active" "PASS"
    else
        log_result "Redis Master" "Not Running" "Container not found" "FAIL"
        return 1
    fi
    
    # Verificar configurações de autenticação
    local redis_auth=$(docker exec fx-redis-master redis-cli CONFIG GET requirepass 2>/dev/null | tail -1)
    if [[ -n "$redis_auth" && "$redis_auth" != "" ]]; then
        log_result "Redis Authentication" "Enabled" "Password protection is active" "PASS"
    else
        log_result "Redis Authentication" "Disabled" "No password protection" "WARN"
    fi
    
    # Verificar comandos perigosos
    local dangerous_commands=$(docker exec fx-redis-master redis-cli CONFIG GET rename-command 2>/dev/null)
    if echo "$dangerous_commands" | grep -q "FLUSHDB\|FLUSHALL\|CONFIG\|EVAL"; then
        log_result "Redis Dangerous Commands" "Renamed" "Dangerous commands are renamed" "PASS"
    else
        log_result "Redis Dangerous Commands" "Available" "Dangerous commands not renamed" "WARN"
    fi
}

# Função para verificar configurações do Kong Gateway
check_kong_security() {
    echo -e "\n${BLUE}=== Checking Kong Gateway Security Configuration ===${NC}"
    
    # Verificar se Kong está rodando
    if ! check_service_running "Kong Gateway" "8080"; then
        return 1
    fi
    
    # Verificar plugins de segurança
    local kong_plugins=$(curl -s "http://localhost:8001/plugins" 2>/dev/null)
    
    if [[ -n "$kong_plugins" ]]; then
        # Verificar rate limiting
        if echo "$kong_plugins" | jq -e '.data[] | select(.name == "rate-limiting")' > /dev/null 2>&1; then
            log_result "Kong Rate Limiting" "Enabled" "Rate limiting plugin is active" "PASS"
        else
            log_result "Kong Rate Limiting" "Disabled" "Rate limiting plugin not found" "WARN"
        fi
        
        # Verificar JWT plugin
        if echo "$kong_plugins" | jq -e '.data[] | select(.name == "jwt")' > /dev/null 2>&1; then
            log_result "Kong JWT Plugin" "Enabled" "JWT plugin is active" "PASS"
        else
            log_result "Kong JWT Plugin" "Disabled" "JWT plugin not found" "WARN"
        fi
        
        # Verificar CORS plugin
        if echo "$kong_plugins" | jq -e '.data[] | select(.name == "cors")' > /dev/null 2>&1; then
            log_result "Kong CORS Plugin" "Enabled" "CORS plugin is active" "PASS"
        else
            log_result "Kong CORS Plugin" "Disabled" "CORS plugin not found" "WARN"
        fi
    else
        log_result "Kong Plugins" "Not Accessible" "Cannot access Kong admin API" "FAIL"
    fi
}

# Função para verificar configurações do Vault
check_vault_security() {
    echo -e "\n${BLUE}=== Checking Vault Security Configuration ===${NC}"
    
    # Verificar se Vault está rodando
    if ! check_service_running "Vault" "8200"; then
        return 1
    fi
    
    # Verificar status do Vault
    local vault_status=$(curl -s "http://localhost:8200/v1/sys/health" 2>/dev/null)
    
    if [[ -n "$vault_status" ]]; then
        local sealed=$(echo "$vault_status" | jq -r '.sealed' 2>/dev/null)
        if [[ "$sealed" == "false" ]]; then
            log_result "Vault Status" "Unsealed" "Vault is operational" "PASS"
        else
            log_result "Vault Status" "Sealed" "Vault is sealed" "WARN"
        fi
        
        local initialized=$(echo "$vault_status" | jq -r '.initialized' 2>/dev/null)
        if [[ "$initialized" == "true" ]]; then
            log_result "Vault Initialization" "Initialized" "Vault is initialized" "PASS"
        else
            log_result "Vault Initialization" "Not Initialized" "Vault needs initialization" "FAIL"
        fi
    else
        log_result "Vault Health" "Not Accessible" "Cannot access Vault health endpoint" "FAIL"
    fi
}

# Função para verificar configurações de rede Docker
check_docker_network_security() {
    echo -e "\n${BLUE}=== Checking Docker Network Security ===${NC}"
    
    # Verificar se a rede privada existe
    if docker network ls | grep -q "fusionx-net"; then
        log_result "Docker Private Network" "Exists" "fusionx-net network is configured" "PASS"
    else
        log_result "Docker Private Network" "Missing" "Private network not found" "FAIL"
    fi
    
    # Verificar isolamento de containers
    local containers_in_network=$(docker network inspect fusionx-net | jq -r '.[0].Containers | keys[]' 2>/dev/null | wc -l)
    if [[ "$containers_in_network" -gt 0 ]]; then
        log_result "Container Network Isolation" "Active" "$containers_in_network containers in private network" "PASS"
    else
        log_result "Container Network Isolation" "Inactive" "No containers in private network" "WARN"
    fi
}

# Função para verificar logs de segurança
check_security_logging() {
    echo -e "\n${BLUE}=== Checking Security Logging Configuration ===${NC}"
    
    # Verificar se os containers estão gerando logs
    local services=("fx-ms-orchestrator" "fx-ms-alert" "fx-ms-customer" "fx-ms-enrichment" "fx-ms-transaction" "fx-ms-api")
    
    for service in "${services[@]}"; do
        if docker ps | grep -q "$service"; then
            local log_lines=$(docker logs "$service" --since="1m" 2>/dev/null | wc -l)
            if [[ "$log_lines" -gt 0 ]]; then
                log_result "$service Logging" "Active" "$log_lines log lines in last minute" "PASS"
            else
                log_result "$service Logging" "Inactive" "No recent log activity" "WARN"
            fi
        else
            log_result "$service Logging" "Service Down" "Container not running" "FAIL"
        fi
    done
}

# Função para verificar configurações de SSL/TLS
check_ssl_configuration() {
    echo -e "\n${BLUE}=== Checking SSL/TLS Configuration ===${NC}"
    
    # Verificar se HTTPS está configurado (em produção)
    if [[ "${ENVIRONMENT:-development}" == "production" ]]; then
        # Em produção, verificar certificados SSL
        local ssl_check=$(curl -s -I "https://localhost:8443" 2>/dev/null | head -1)
        if echo "$ssl_check" | grep -q "200\|301\|302"; then
            log_result "HTTPS Configuration" "Active" "HTTPS endpoint is accessible" "PASS"
        else
            log_result "HTTPS Configuration" "Inactive" "HTTPS endpoint not accessible" "FAIL"
        fi
    else
        log_result "HTTPS Configuration" "Development Mode" "SSL not required in development" "INFO"
    fi
    
    # Verificar redirecionamento HTTP para HTTPS
    local http_redirect=$(curl -s -I "http://localhost:8080" 2>/dev/null | grep -i "location:")
    if echo "$http_redirect" | grep -q "https://"; then
        log_result "HTTP to HTTPS Redirect" "Configured" "HTTP requests are redirected to HTTPS" "PASS"
    else
        log_result "HTTP to HTTPS Redirect" "Not Configured" "HTTP requests not redirected" "WARN"
    fi
}

# Função principal
main() {
    echo -e "${BLUE}Eagle System Security Configuration Validator${NC}"
    echo -e "${BLUE}=============================================${NC}"
    
    # Verificar dependências
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: jq is not installed, some checks will be limited${NC}"
    fi
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: docker is required but not installed${NC}"
        exit 1
    fi
    
    # Executar verificações
    check_docker_network_security
    check_postgresql_security
    check_redis_security
    check_keycloak_security
    check_kong_security
    check_vault_security
    
    # Verificar microserviços
    local services=(
        "ms-orchestrator:8088"
        "ms-alert:8083"
        "ms-customer:8085"
        "ms-enrichment:8082"
        "ms-transaction:8086"
        "ms-api:8087"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        if check_service_running "$service_name" "$port"; then
            check_spring_security_config "$service_name" "$port"
            check_security_headers "$service_name" "$port"
        fi
    done
    
    check_ssl_configuration
    check_security_logging
    
    # Relatório final
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}SECURITY CONFIGURATION VALIDATION REPORT${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total checks: $TOTAL_CHECKS"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
    echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}"
    
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        echo -e "\n${RED}⚠️  CRITICAL SECURITY ISSUES FOUND: $FAILED_CHECKS${NC}"
        echo -e "${RED}Please review and fix the failed checks before deploying to production.${NC}"
        exit 1
    elif [[ $WARNING_CHECKS -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠️  SECURITY WARNINGS: $WARNING_CHECKS${NC}"
        echo -e "${YELLOW}Consider addressing the warnings to improve security posture.${NC}"
        exit 0
    else
        echo -e "\n${GREEN}✅ All security checks passed!${NC}"
        exit 0
    fi
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi