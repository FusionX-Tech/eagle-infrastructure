-- Content Security Policy Plugin for Kong
-- This plugin adds comprehensive security headers to responses

local CSPHandler = {}

CSPHandler.PRIORITY = 1000
CSPHandler.VERSION = "1.0.0"

function CSPHandler:header_filter(conf)
    -- Content Security Policy
    local csp_policy = table.concat({
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://unpkg.com",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net",
        "font-src 'self' https://fonts.gstatic.com https://cdn.jsdelivr.net",
        "img-src 'self' data: https: blob:",
        "connect-src 'self' https://api.eagle.fusionx.com.br wss://api.eagle.fusionx.com.br",
        "media-src 'self'",
        "object-src 'none'",
        "child-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "upgrade-insecure-requests"
    }, "; ")
    
    kong.response.set_header("Content-Security-Policy", csp_policy)
    
    -- Additional Security Headers
    kong.response.set_header("X-Content-Type-Options", "nosniff")
    kong.response.set_header("X-Frame-Options", "DENY")
    kong.response.set_header("X-XSS-Protection", "1; mode=block")
    kong.response.set_header("Referrer-Policy", "strict-origin-when-cross-origin")
    kong.response.set_header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
    
    -- HSTS (HTTP Strict Transport Security)
    if kong.request.get_scheme() == "https" then
        kong.response.set_header("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload")
    end
    
    -- Remove server information
    kong.response.clear_header("Server")
    kong.response.clear_header("X-Powered-By")
    
    -- Add custom security headers
    kong.response.set_header("X-API-Version", "v1.0")
    kong.response.set_header("X-Security-Policy", "eagle-security-v1")
end

return CSPHandler