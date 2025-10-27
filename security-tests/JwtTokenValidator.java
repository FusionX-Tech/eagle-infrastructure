package com.eagle.security.utils;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;

/**
 * Utilitário para validação e geração de tokens JWT para testes de segurança
 * 
 * Esta classe fornece métodos para:
 * - Validar tokens JWT
 * - Gerar tokens para testes
 * - Verificar claims e roles
 * - Detectar vulnerabilidades em tokens
 */
@Component
public class JwtTokenValidator {

    private final ObjectMapper objectMapper;
    private final SecretKey defaultTestKey;
    
    // Configurações padrão para testes
    private static final String DEFAULT_ISSUER = "http://localhost:8081/realms/eagle-dev";
    private static final String DEFAULT_AUDIENCE = "eagle-services";
    private static final long DEFAULT_EXPIRATION_HOURS = 1;

    public JwtTokenValidator() {
        this.objectMapper = new ObjectMapper();
        // Chave de teste - NÃO usar em produção
        this.defaultTestKey = Keys.hmacShaKeyFor(
            "test-secret-key-for-eagle-security-testing-only-do-not-use-in-production".getBytes(StandardCharsets.UTF_8)
        );
    }

    /**
     * Valida um token JWT e retorna informações sobre sua segurança
     */
    public TokenValidationResult validateToken(String token) {
        TokenValidationResult result = new TokenValidationResult();
        result.token = token;
        result.isValid = false;
        result.vulnerabilities = new ArrayList<>();
        result.claims = new HashMap<>();

        try {
            // Tentar parsear o token sem validação de assinatura primeiro
            String[] parts = token.split("\\.");
            if (parts.length != 3) {
                result.vulnerabilities.add("Token malformado - deve ter 3 partes separadas por '.'");
                return result;
            }

            // Decodificar header
            String headerJson = new String(Base64.getUrlDecoder().decode(parts[0]));
            Map<String, Object> header = objectMapper.readValue(headerJson, Map.class);
            result.header = header;

            // Verificar algoritmo
            String algorithm = (String) header.get("alg");
            if ("none".equals(algorithm)) {
                result.vulnerabilities.add("CRÍTICO: Algoritmo 'none' não é seguro");
            } else if ("HS256".equals(algorithm)) {
                result.vulnerabilities.add("AVISO: HS256 é menos seguro que RS256 para produção");
            }

            // Decodificar payload
            String payloadJson = new String(Base64.getUrlDecoder().decode(parts[1]));
            Map<String, Object> payload = objectMapper.readValue(payloadJson, Map.class);
            result.claims = payload;

            // Verificar claims obrigatórios
            validateRequiredClaims(result, payload);

            // Verificar expiração
            validateExpiration(result, payload);

            // Verificar issuer
            validateIssuer(result, payload);

            // Verificar audience
            validateAudience(result, payload);

            // Verificar roles
            validateRoles(result, payload);

            // Tentar validar assinatura com chave de teste
            try {
                Jwts.parserBuilder()
                    .setSigningKey(defaultTestKey)
                    .build()
                    .parseClaimsJws(token);
                result.isValid = true;
            } catch (JwtException e) {
                result.vulnerabilities.add("Assinatura inválida ou chave incorreta: " + e.getMessage());
            }

        } catch (Exception e) {
            result.vulnerabilities.add("Erro ao processar token: " + e.getMessage());
        }

        return result;
    }

    /**
     * Gera um token JWT válido para testes
     */
    public String generateValidTestToken(String subject, String[] roles) {
        Instant now = Instant.now();
        
        Map<String, Object> realmAccess = new HashMap<>();
        realmAccess.put("roles", Arrays.asList(roles));
        
        return Jwts.builder()
                .setSubject(subject)
                .setIssuer(DEFAULT_ISSUER)
                .setAudience(DEFAULT_AUDIENCE)
                .setIssuedAt(Date.from(now))
                .setExpiration(Date.from(now.plus(DEFAULT_EXPIRATION_HOURS, ChronoUnit.HOURS)))
                .claim("realm_access", realmAccess)
                .claim("preferred_username", subject)
                .claim("email", subject + "@eagle.com")
                .signWith(defaultTestKey)
                .compact();
    }

    /**
     * Gera um token JWT expirado para testes
     */
    public String generateExpiredTestToken(String subject) {
        Instant now = Instant.now();
        
        return Jwts.builder()
                .setSubject(subject)
                .setIssuer(DEFAULT_ISSUER)
                .setAudience(DEFAULT_AUDIENCE)
                .setIssuedAt(Date.from(now.minus(2, ChronoUnit.HOURS)))
                .setExpiration(Date.from(now.minus(1, ChronoUnit.HOURS)))
                .claim("realm_access", Map.of("roles", Arrays.asList("USER")))
                .signWith(defaultTestKey)
                .compact();
    }

    /**
     * Gera um token JWT com assinatura inválida para testes
     */
    public String generateInvalidSignatureToken(String subject) {
        SecretKey wrongKey = Keys.hmacShaKeyFor("wrong-key".getBytes(StandardCharsets.UTF_8));
        
        return Jwts.builder()
                .setSubject(subject)
                .setIssuer(DEFAULT_ISSUER)
                .setAudience(DEFAULT_AUDIENCE)
                .setExpiration(Date.from(Instant.now().plus(1, ChronoUnit.HOURS)))
                .signWith(wrongKey)
                .compact();
    }

    /**
     * Gera um token JWT sem algoritmo (vulnerabilidade crítica)
     */
    public String generateNoneAlgorithmToken(String subject) {
        // Token com algoritmo "none" - NUNCA usar em produção
        String header = "{\"alg\":\"none\",\"typ\":\"JWT\"}";
        String payload = String.format(
            "{\"sub\":\"%s\",\"iss\":\"%s\",\"aud\":\"%s\",\"exp\":%d}",
            subject, DEFAULT_ISSUER, DEFAULT_AUDIENCE,
            Instant.now().plus(1, ChronoUnit.HOURS).getEpochSecond()
        );
        
        String encodedHeader = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(header.getBytes(StandardCharsets.UTF_8));
        String encodedPayload = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(payload.getBytes(StandardCharsets.UTF_8));
        
        return encodedHeader + "." + encodedPayload + ".";
    }

    /**
     * Gera tokens malformados para testes
     */
    public List<String> generateMalformedTokens() {
        return Arrays.asList(
            "invalid.jwt.token",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            "",
            "not-a-jwt-token",
            "header.payload", // Faltando assinatura
            "header.payload.signature.extra" // Muitas partes
        );
    }

    private void validateRequiredClaims(TokenValidationResult result, Map<String, Object> payload) {
        String[] requiredClaims = {"sub", "iss", "aud", "exp", "iat"};
        
        for (String claim : requiredClaims) {
            if (!payload.containsKey(claim)) {
                result.vulnerabilities.add("Claim obrigatório ausente: " + claim);
            }
        }
    }

    private void validateExpiration(TokenValidationResult result, Map<String, Object> payload) {
        Object expObj = payload.get("exp");
        if (expObj != null) {
            try {
                long exp = ((Number) expObj).longValue();
                long now = Instant.now().getEpochSecond();
                
                if (exp < now) {
                    result.vulnerabilities.add("Token expirado");
                } else if (exp > now + (365 * 24 * 60 * 60)) { // 1 ano
                    result.vulnerabilities.add("AVISO: Token com expiração muito longa (> 1 ano)");
                }
            } catch (Exception e) {
                result.vulnerabilities.add("Claim 'exp' inválido: " + e.getMessage());
            }
        }
    }

    private void validateIssuer(TokenValidationResult result, Map<String, Object> payload) {
        Object issObj = payload.get("iss");
        if (issObj != null) {
            String issuer = issObj.toString();
            if (!issuer.startsWith("http://") && !issuer.startsWith("https://")) {
                result.vulnerabilities.add("AVISO: Issuer não é uma URL válida");
            }
            if (issuer.startsWith("http://") && !issuer.contains("localhost")) {
                result.vulnerabilities.add("AVISO: Issuer usando HTTP em ambiente não-local");
            }
        }
    }

    private void validateAudience(TokenValidationResult result, Map<String, Object> payload) {
        Object audObj = payload.get("aud");
        if (audObj != null) {
            String audience = audObj.toString();
            if (audience.isEmpty()) {
                result.vulnerabilities.add("Audience vazio");
            }
        }
    }

    private void validateRoles(TokenValidationResult result, Map<String, Object> payload) {
        // Verificar realm_access roles
        Object realmAccessObj = payload.get("realm_access");
        if (realmAccessObj instanceof Map) {
            Map<String, Object> realmAccess = (Map<String, Object>) realmAccessObj;
            Object rolesObj = realmAccess.get("roles");
            
            if (rolesObj instanceof List) {
                List<String> roles = (List<String>) rolesObj;
                result.roles = roles;
                
                if (roles.isEmpty()) {
                    result.vulnerabilities.add("AVISO: Nenhuma role definida");
                }
                
                // Verificar roles perigosas
                if (roles.contains("admin") || roles.contains("ADMIN")) {
                    result.vulnerabilities.add("AVISO: Token contém role administrativa");
                }
            }
        } else {
            result.vulnerabilities.add("AVISO: Estrutura de roles não encontrada");
        }
    }

    /**
     * Classe para resultado da validação de token
     */
    public static class TokenValidationResult {
        public String token;
        public boolean isValid;
        public List<String> vulnerabilities;
        public Map<String, Object> header;
        public Map<String, Object> claims;
        public List<String> roles;

        public TokenValidationResult() {
            this.vulnerabilities = new ArrayList<>();
            this.claims = new HashMap<>();
            this.roles = new ArrayList<>();
        }

        public boolean hasCriticalVulnerabilities() {
            return vulnerabilities.stream()
                .anyMatch(v -> v.startsWith("CRÍTICO:"));
        }

        public boolean hasWarnings() {
            return vulnerabilities.stream()
                .anyMatch(v -> v.startsWith("AVISO:"));
        }

        public String getSummary() {
            StringBuilder summary = new StringBuilder();
            summary.append("Token Validation Summary:\n");
            summary.append("Valid: ").append(isValid).append("\n");
            summary.append("Subject: ").append(claims.get("sub")).append("\n");
            summary.append("Issuer: ").append(claims.get("iss")).append("\n");
            summary.append("Roles: ").append(roles).append("\n");
            summary.append("Vulnerabilities: ").append(vulnerabilities.size()).append("\n");
            
            if (!vulnerabilities.isEmpty()) {
                summary.append("Issues:\n");
                for (String vuln : vulnerabilities) {
                    summary.append("  - ").append(vuln).append("\n");
                }
            }
            
            return summary.toString();
        }
    }

    /**
     * Método utilitário para testes rápidos
     */
    public static void main(String[] args) {
        JwtTokenValidator validator = new JwtTokenValidator();
        
        // Gerar e validar token válido
        String validToken = validator.generateValidTestToken("test-user", 
            new String[]{"MICROSERVICE", "ALERT_CREATE"});
        System.out.println("Valid Token: " + validToken);
        
        TokenValidationResult result = validator.validateToken(validToken);
        System.out.println(result.getSummary());
        
        // Testar token expirado
        String expiredToken = validator.generateExpiredTestToken("test-user");
        System.out.println("\nExpired Token: " + expiredToken);
        
        result = validator.validateToken(expiredToken);
        System.out.println(result.getSummary());
        
        // Testar token com algoritmo "none"
        String noneToken = validator.generateNoneAlgorithmToken("test-user");
        System.out.println("\nNone Algorithm Token: " + noneToken);
        
        result = validator.validateToken(noneToken);
        System.out.println(result.getSummary());
    }
}