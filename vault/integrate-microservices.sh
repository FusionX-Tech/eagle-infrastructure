#!/bin/bash

set -e

echo "🔐 Integrating HashiCorp Vault with all microservices..."

# List of microservices to integrate
MICROSERVICES=("ms-customer" "ms-transaction" "ms-api" "ms-enrichment" "ms-orchestrator")

# Function to add Vault dependencies to build.gradle
add_vault_dependencies() {
    local service=$1
    local build_file="services/${service}/build.gradle"
    
    if [ -f "$build_file" ]; then
        echo "📝 Adding Vault dependencies to ${service}..."
        
        # Check if Vault dependencies are already added
        if ! grep -q "spring-vault-core" "$build_file"; then
            # Find the line with spring-boot-starter-data-redis or similar and add Vault deps after it
            if grep -q "spring-boot-starter-data-redis" "$build_file"; then
                sed -i "/spring-boot-starter-data-redis/a\\
\\
  // HashiCorp Vault integration\\
  implementation 'org.springframework.vault:spring-vault-core:3.1.1'\\
  implementation 'org.springframework.cloud:spring-cloud-vault-config:4.1.3'\\
  implementation 'com.zaxxer:HikariCP'                                     // Connection pooling" "$build_file"
            else
                # If no redis dependency, add after the last implementation line before testImplementation
                sed -i "/implementation.*$/a\\
\\
  // HashiCorp Vault integration\\
  implementation 'org.springframework.vault:spring-vault-core:3.1.1'\\
  implementation 'org.springframework.cloud:spring-cloud-vault-config:4.1.3'\\
  implementation 'com.zaxxer:HikariCP'                                     // Connection pooling\\
  implementation 'org.springframework.boot:spring-boot-starter-data-redis' // Redis support" "$build_file"
            fi
            echo "  ✅ Added Vault dependencies to ${service}"
        else
            echo "  ⚠️  Vault dependencies already exist in ${service}"
        fi
    else
        echo "  ❌ Build file not found: ${build_file}"
    fi
}

# Function to create Vault configuration files
create_vault_config() {
    local service=$1
    local java_path="services/${service}/src/main/java"
    local resources_path="services/${service}/src/main/resources"
    
    echo "📁 Creating Vault configuration for ${service}..."
    
    # Find the main package path
    local package_path=$(find "$java_path" -name "*.java" -type f | head -1 | xargs dirname | sed "s|$java_path/||")
    local vault_path="${java_path}/${package_path}/vault"
    
    if [ ! -z "$package_path" ]; then
        mkdir -p "$vault_path"
        
        # Get the package name from the path
        local package_name=$(echo "$package_path" | tr '/' '.')
        
        # Create VaultConfig.java
        cat > "${vault_path}/VaultConfig.java" << EOF
package ${package_name}.vault;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.vault.authentication.AppRoleAuthentication;
import org.springframework.vault.authentication.AppRoleAuthenticationOptions;
import org.springframework.vault.client.VaultEndpoint;
import org.springframework.vault.config.AbstractVaultConfiguration;
import org.springframework.vault.core.VaultTemplate;

import java.net.URI;

/**
 * Configuration for HashiCorp Vault integration in ${service}
 */
@Configuration
public class VaultConfig extends AbstractVaultConfiguration {

    @Value("\${vault.uri:http://vault:8200}")
    private String vaultUri;

    @Value("\${vault.role-id}")
    private String roleId;

    @Value("\${vault.secret-id}")
    private String secretId;

    @Override
    public VaultEndpoint vaultEndpoint() {
        return VaultEndpoint.from(URI.create(vaultUri));
    }

    @Override
    public AppRoleAuthentication clientAuthentication() {
        AppRoleAuthenticationOptions options = AppRoleAuthenticationOptions.builder()
                .roleId(roleId)
                .secretId(secretId)
                .path("approle")
                .build();

        return new AppRoleAuthentication(options, restOperations());
    }

    @Bean
    public VaultTemplate vaultTemplate() {
        return new VaultTemplate(vaultEndpoint(), clientAuthentication());
    }
}
EOF

        # Create VaultSecretService.java
        cat > "${vault_path}/VaultSecretService.java" << EOF
package ${package_name}.vault;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.vault.core.VaultTemplate;
import org.springframework.vault.support.VaultResponse;

import java.util.Map;
import java.util.Optional;

/**
 * Service for retrieving secrets from HashiCorp Vault in ${service}
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class VaultSecretService {

    private final VaultTemplate vaultTemplate;

    public Optional<String> getSecret(String path, String key) {
        try {
            VaultResponse response = vaultTemplate.read("secret/data/" + path);
            if (response != null && response.getData() != null) {
                @SuppressWarnings("unchecked")
                Map<String, Object> data = (Map<String, Object>) response.getData().get("data");
                if (data != null && data.containsKey(key)) {
                    return Optional.of(data.get(key).toString());
                }
            }
            log.warn("Secret not found: path={}, key={}", path, key);
            return Optional.empty();
        } catch (Exception e) {
            log.error("Error retrieving secret from Vault: path={}, key={}", path, key, e);
            return Optional.empty();
        }
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> getAllSecrets(String path) {
        try {
            VaultResponse response = vaultTemplate.read("secret/data/" + path);
            if (response != null && response.getData() != null) {
                return (Map<String, Object>) response.getData().get("data");
            }
            log.warn("No secrets found at path: {}", path);
            return Map.of();
        } catch (Exception e) {
            log.error("Error retrieving secrets from Vault: path={}", path, e);
            return Map.of();
        }
    }
}
EOF

        # Create VaultHealthIndicator.java
        cat > "${vault_path}/VaultHealthIndicator.java" << EOF
package ${package_name}.vault;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.actuator.health.Health;
import org.springframework.boot.actuator.health.HealthIndicator;
import org.springframework.stereotype.Component;
import org.springframework.vault.core.VaultTemplate;
import org.springframework.vault.support.VaultHealth;

/**
 * Health indicator for HashiCorp Vault connectivity in ${service}
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class VaultHealthIndicator implements HealthIndicator {

    private final VaultTemplate vaultTemplate;

    @Override
    public Health health() {
        try {
            VaultHealth vaultHealth = vaultTemplate.opsForSys().health();
            
            if (vaultHealth.isInitialized() && !vaultHealth.isSealed()) {
                return Health.up()
                        .withDetail("service", "${service}")
                        .withDetail("status", "UP")
                        .withDetail("initialized", vaultHealth.isInitialized())
                        .withDetail("sealed", vaultHealth.isSealed())
                        .build();
            } else {
                return Health.down()
                        .withDetail("service", "${service}")
                        .withDetail("status", "DOWN")
                        .withDetail("reason", vaultHealth.isSealed() ? "Vault is sealed" : "Vault not initialized")
                        .build();
            }
        } catch (Exception e) {
            log.error("Vault health check failed in ${service}", e);
            return Health.down()
                    .withDetail("service", "${service}")
                    .withDetail("status", "DOWN")
                    .withDetail("error", e.getMessage())
                    .build();
        }
    }
}
EOF

        echo "  ✅ Created Vault configuration files for ${service}"
    else
        echo "  ❌ Could not determine package structure for ${service}"
    fi
    
    # Create vault-application.yml
    if [ ! -f "${resources_path}/vault-application.yml" ]; then
        mkdir -p "$resources_path"
        cat > "${resources_path}/vault-application.yml" << EOF
# Vault configuration for ${service}
vault:
  uri: \${VAULT_ADDR:http://vault:8200}
  role-id: \${VAULT_ROLE_ID:}
  secret-id: \${VAULT_SECRET_ID:}
  
  database:
    dynamic-credentials:
      enabled: \${VAULT_DYNAMIC_DB_ENABLED:false}
  redis:
    enabled: \${VAULT_REDIS_ENABLED:true}
  aws:
    enabled: \${VAULT_AWS_ENABLED:true}
  management:
    enabled: \${VAULT_MANAGEMENT_ENABLED:false}

spring:
  cloud:
    vault:
      enabled: true
      uri: \${vault.uri}
      authentication: APPROLE
      app-role:
        role-id: \${vault.role-id}
        secret-id: \${vault.secret-id}
        app-role-path: approle
      kv:
        enabled: true
        backend: secret
        default-context: microservices

management:
  endpoints:
    web:
      exposure:
        include: health,info,vault,metrics
  health:
    vault:
      enabled: true

logging:
  level:
    org.springframework.vault: INFO
    ${package_name}.vault: DEBUG
EOF
        echo "  ✅ Created vault-application.yml for ${service}"
    fi
    
    # Update application.yml to import vault configuration
    local app_yml="${resources_path}/application.yml"
    if [ -f "$app_yml" ] && ! grep -q "vault-application.yml" "$app_yml"; then
        # Add import after spring: application: name:
        sed -i '/spring:/,/application:/{
            /name:/a\
  config:\
    import: \
      - classpath:vault-application.yml
        }' "$app_yml"
        echo "  ✅ Updated application.yml for ${service}"
    fi
}

# Function to update .env files
update_env_file() {
    local service=$1
    local env_file="services/${service}/.env"
    
    echo "📝 Updating .env file for ${service}..."
    
    if [ -f "$env_file" ]; then
        # Add Vault configuration if not already present
        if ! grep -q "VAULT_ADDR" "$env_file"; then
            cat >> "$env_file" << EOF

# HashiCorp Vault Configuration
VAULT_ADDR=http://vault:8200
VAULT_ROLE_ID=
VAULT_SECRET_ID=
VAULT_DYNAMIC_DB_ENABLED=false
VAULT_REDIS_ENABLED=true
VAULT_AWS_ENABLED=true
VAULT_MANAGEMENT_ENABLED=false
EOF
            echo "  ✅ Added Vault configuration to ${service}/.env"
        else
            echo "  ⚠️  Vault configuration already exists in ${service}/.env"
        fi
    else
        echo "  ❌ .env file not found: ${env_file}"
    fi
}

# Process each microservice
for service in "${MICROSERVICES[@]}"; do
    echo ""
    echo "🔧 Processing ${service}..."
    
    add_vault_dependencies "$service"
    create_vault_config "$service"
    update_env_file "$service"
    
    echo "✅ Completed integration for ${service}"
done

echo ""
echo "🎉 Vault integration completed for all microservices!"
echo ""
echo "📝 Next steps:"
echo "  1. Run: ./infra/vault/update-env-files.sh"
echo "  2. Restart services: docker-compose restart ms-customer ms-transaction ms-api ms-enrichment ms-orchestrator"
echo "  3. Verify health: curl http://localhost:8083/actuator/health/vault"