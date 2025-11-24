# Eagle Flow Integration Dashboard Validation Script

Write-Host "=== Eagle Flow Integration Dashboard Validation ===" -ForegroundColor Cyan
Write-Host ""

# Check 1: Dashboard file exists
Write-Host "1. Checking dashboard file..." -ForegroundColor Yellow
$dashboardPath = "grafana\dashboards\infrastructure\eagle-flow-integration-dashboard.json"
if (Test-Path $dashboardPath) {
    Write-Host "   ✓ Dashboard file exists" -ForegroundColor Green
    $dashboardSize = (Get-Item $dashboardPath).Length
    Write-Host "   Size: $dashboardSize bytes" -ForegroundColor Gray
} else {
    Write-Host "   ✗ Dashboard file NOT found" -ForegroundColor Red
    exit 1
}

# Check 2: README exists
Write-Host ""
Write-Host "2. Checking documentation..." -ForegroundColor Yellow
$readmePath = "grafana\dashboards\infrastructure\EAGLE_FLOW_INTEGRATION_DASHBOARD_README.md"
if (Test-Path $readmePath) {
    Write-Host "   ✓ README exists" -ForegroundColor Green
} else {
    Write-Host "   ✗ README NOT found" -ForegroundColor Red
}

# Check 3: Prometheus config includes Eagle Flow
Write-Host ""
Write-Host "3. Checking Prometheus configuration..." -ForegroundColor Yellow
$prometheusConfig = Get-Content "prometheus.yml" -Raw
if ($prometheusConfig -match "ms-eagle-flow") {
    Write-Host "   ✓ Eagle Flow scrape config found" -ForegroundColor Green
} else {
    Write-Host "   ✗ Eagle Flow scrape config NOT found" -ForegroundColor Red
    Write-Host "   Add the following to prometheus.yml:" -ForegroundColor Yellow
    Write-Host @"
  - job_name: 'ms-eagle-flow'
    static_configs:
      - targets: ['fx-ms-eagle-flow:8092']
    scrape_interval: 15s
    metrics_path: /actuator/prometheus
"@ -ForegroundColor Gray
}

# Check 4: Docker containers running
Write-Host ""
Write-Host "4. Checking Docker containers..." -ForegroundColor Yellow
try {
    $containers = docker ps --format "{{.Names}}" 2>$null
    
    if ($containers -match "eagle-grafana") {
        Write-Host "   ✓ Grafana container running" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Grafana container NOT running" -ForegroundColor Red
        Write-Host "   Start with: .\start-monitoring.ps1" -ForegroundColor Yellow
    }
    
    if ($containers -match "eagle-prometheus") {
        Write-Host "   ✓ Prometheus container running" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Prometheus container NOT running" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Docker not available or not running" -ForegroundColor Red
}

# Check 5: Grafana accessibility
Write-Host ""
Write-Host "5. Checking Grafana accessibility..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -TimeoutSec 5 -UseBasicParsing 2>$null
    if ($response.StatusCode -eq 200) {
        Write-Host "   ✓ Grafana is accessible at http://localhost:3000" -ForegroundColor Green
    }
} catch {
    Write-Host "   ✗ Grafana is NOT accessible" -ForegroundColor Red
    Write-Host "   Check if container is running and port 3000 is available" -ForegroundColor Yellow
}

# Check 6: Prometheus accessibility
Write-Host ""
Write-Host "6. Checking Prometheus accessibility..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:9090/-/healthy" -TimeoutSec 5 -UseBasicParsing 2>$null
    if ($response.StatusCode -eq 200) {
        Write-Host "   ✓ Prometheus is accessible at http://localhost:9090" -ForegroundColor Green
    }
} catch {
    Write-Host "   ✗ Prometheus is NOT accessible" -ForegroundColor Red
    Write-Host "   Check if container is running and port 9090 is available" -ForegroundColor Yellow
}

# Check 7: Eagle Flow metrics endpoint
Write-Host ""
Write-Host "7. Checking Eagle Flow metrics endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8092/actuator/prometheus" -TimeoutSec 5 -UseBasicParsing 2>$null
    if ($response.StatusCode -eq 200) {
        Write-Host "   ✓ Eagle Flow metrics endpoint is accessible" -ForegroundColor Green
        
        # Check for specific metrics
        $content = $response.Content
        if ($content -match "eagle_flow_integration_calls_total") {
            Write-Host "   ✓ Integration calls metric found" -ForegroundColor Green
        } else {
            Write-Host "   ⚠ Integration calls metric NOT found (may need traffic)" -ForegroundColor Yellow
        }
        
        if ($content -match "eagle_flow_circuit_breaker_state") {
            Write-Host "   ✓ Circuit breaker metric found" -ForegroundColor Green
        } else {
            Write-Host "   ⚠ Circuit breaker metric NOT found (may need traffic)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "   ✗ Eagle Flow metrics endpoint is NOT accessible" -ForegroundColor Red
    Write-Host "   Check if Eagle Flow is running on port 8092" -ForegroundColor Yellow
}

# Check 8: Prometheus targets
Write-Host ""
Write-Host "8. Checking Prometheus targets..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:9090/api/v1/targets" -TimeoutSec 5 -UseBasicParsing 2>$null
    if ($response.StatusCode -eq 200) {
        $targets = $response.Content | ConvertFrom-Json
        $eagleFlowTarget = $targets.data.activeTargets | Where-Object { $_.job -eq "ms-eagle-flow" }
        
        if ($eagleFlowTarget) {
            if ($eagleFlowTarget.health -eq "up") {
                Write-Host "   ✓ Eagle Flow target is UP in Prometheus" -ForegroundColor Green
            } else {
                Write-Host "   ✗ Eagle Flow target is DOWN in Prometheus" -ForegroundColor Red
                Write-Host "   Error: $($eagleFlowTarget.lastError)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "   ✗ Eagle Flow target NOT found in Prometheus" -ForegroundColor Red
            Write-Host "   Reload Prometheus config: curl -X POST http://localhost:9090/-/reload" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "   ✗ Could not check Prometheus targets" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "=== Validation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Access Grafana: http://localhost:3000 (admin/admin)" -ForegroundColor Gray
Write-Host "2. Navigate to: Dashboards → Eagle Infrastructure → Eagle Flow - Integration Health" -ForegroundColor Gray
Write-Host "3. Generate test traffic to populate metrics" -ForegroundColor Gray
Write-Host "4. Read the setup guide: DASHBOARD_SETUP_GUIDE.md" -ForegroundColor Gray
Write-Host ""
