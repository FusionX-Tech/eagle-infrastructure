# Eagle Infrastructure Startup Script (PowerShell)
# Segue a ordem obrigatória de inicialização definida nos princípios

param(
    [switch]$SkipHealthChecks = $false
)

Write-Host "🚀 Iniciando Eagle Infrastructure..." -ForegroundColor Cyan
Write-Host "📋 Seguindo ordem obrigatória de dependências" -ForegroundColor Yellow

# Função para aguardar serviço ficar saudável
function Wait-ForService {
    param(
        [string]$ServiceName,
        [int]$Port,
        [int]$MaxAttempts = 30
    )
    
    if ($SkipHealthChecks) {
        Write-Host "⏭️  Pulando health check para $ServiceName" -ForegroundColor Yellow
        return $true
    }
    
    Write-Host "⏳ Aguardando $ServiceName ficar disponível..." -ForegroundColor Yellow
    
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $dockerStatus = docker-compose ps $ServiceName
            if ($dockerStatus -match "Up") {
                $connection = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue
                if ($connection.TcpTestSucceeded) {
                    Write-Host "✅ $ServiceName está disponível!" -ForegroundColor Green
                    return $true
                }
            }
        }
        catch {
            # Continua tentando
        }
        
        Write-Host "   Tentativa $attempt/$MaxAttempts..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    
    Write-Host "❌ $ServiceName não ficou disponível após $MaxAttempts tentativas" -ForegroundColor Red
    return $false
}

try {
    # 1. Infrastructure Base
    Write-Host "`n📦 1. Iniciando Infrastructure Base (PostgreSQL, Redis)" -ForegroundColor Blue
    docker-compose up -d postgres redis
    
    if (-not (Wait-ForService "postgres" 5432)) { throw "PostgreSQL falhou" }
    if (-not (Wait-ForService "redis" 6379)) { throw "Redis falhou" }
    
    # 2. Platform Services
    Write-Host "`n🔐 2. Iniciando Platform Services (Keycloak, Kong, Vault)" -ForegroundColor Blue
    docker-compose up -d keycloak kong vault
    
    if (-not (Wait-ForService "keycloak" 8080)) { throw "Keycloak falhou" }
    if (-not (Wait-ForService "kong" 8000)) { throw "Kong falhou" }
    if (-not (Wait-ForService "vault" 8200)) { throw "Vault falhou" }
    
    # 3. Monitoring
    Write-Host "`n📊 3. Iniciando Monitoring (Prometheus, Grafana, Jaeger)" -ForegroundColor Blue
    docker-compose up -d prometheus grafana jaeger
    
    if (-not (Wait-ForService "prometheus" 9090)) { throw "Prometheus falhou" }
    if (-not (Wait-ForService "grafana" 3000)) { throw "Grafana falhou" }
    if (-not (Wait-ForService "jaeger" 16686)) { throw "Jaeger falhou" }
    
    # 4. Verificação final
    Write-Host "`n🔍 4. Verificação Final" -ForegroundColor Blue
    Write-Host "✅ Infraestrutura iniciada com sucesso!" -ForegroundColor Green
    
    Write-Host "`n📋 Serviços Disponíveis:" -ForegroundColor Blue
    Write-Host "  🗄️  PostgreSQL:  localhost:5432" -ForegroundColor White
    Write-Host "  🔴 Redis:        localhost:6379" -ForegroundColor White
    Write-Host "  🔐 Keycloak:     http://localhost:8080" -ForegroundColor White
    Write-Host "  🌐 Kong:         http://localhost:8000" -ForegroundColor White
    Write-Host "  🔒 Vault:        http://localhost:8200" -ForegroundColor White
    Write-Host "  📊 Prometheus:   http://localhost:9090" -ForegroundColor White
    Write-Host "  📈 Grafana:      http://localhost:3000" -ForegroundColor White
    Write-Host "  🔍 Jaeger:       http://localhost:16686" -ForegroundColor White
    
    Write-Host "`n📝 Próximos passos:" -ForegroundColor Yellow
    Write-Host "  1. Configurar Keycloak: cd keycloak; .\scripts\setup-keycloak.ps1" -ForegroundColor White
    Write-Host "  2. Iniciar aplicações: cd ..\eagle-backend; docker-compose up -d" -ForegroundColor White
    
    Write-Host "`n🎉 Eagle Infrastructure está pronta!" -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ Erro durante inicialização: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "🔧 Executando diagnóstico..." -ForegroundColor Yellow
    
    docker-compose ps
    
    Write-Host "`n💡 Dicas para resolução:" -ForegroundColor Yellow
    Write-Host "  - Verifique se as portas não estão em uso: netstat -an | findstr LISTEN" -ForegroundColor White
    Write-Host "  - Verifique logs: docker-compose logs [service-name]" -ForegroundColor White
    Write-Host "  - Reinicie com: docker-compose down && docker-compose up -d" -ForegroundColor White
    
    exit 1
}