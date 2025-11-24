-- 04_ms_api_schema.sql
\c ms_api;

-- Grant permissions to api_user
GRANT ALL ON SCHEMA public TO api_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO api_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO api_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO api_user;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO api_user;

-- Create external_data_cache table
CREATE TABLE IF NOT EXISTS external_data_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document VARCHAR(20) NOT NULL,
    data_source VARCHAR(50) NOT NULL,
    response_data JSONB NOT NULL,
    last_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_external_data_cache_document ON external_data_cache(document);
CREATE INDEX IF NOT EXISTS idx_external_data_cache_data_source ON external_data_cache(data_source);
CREATE INDEX IF NOT EXISTS idx_external_data_cache_document_source ON external_data_cache(document, data_source);
CREATE INDEX IF NOT EXISTS idx_external_data_cache_expires_at ON external_data_cache(expires_at);
CREATE INDEX IF NOT EXISTS idx_external_data_cache_is_active ON external_data_cache(is_active);
CREATE INDEX IF NOT EXISTS idx_external_data_cache_last_updated ON external_data_cache(last_updated);

-- Create composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_external_data_cache_active_document ON external_data_cache(document, is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_external_data_cache_active_source ON external_data_cache(data_source, is_active, expires_at);

-- Create partial indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_external_data_cache_active_only ON external_data_cache(document, data_source, expires_at) 
WHERE is_active = true;

-- Removed problematic partial index with non-immutable function
-- CREATE INDEX IF NOT EXISTS idx_external_data_cache_expired ON external_data_cache(expires_at) 
-- WHERE expires_at < CURRENT_TIMESTAMP;

-- Add constraints
ALTER TABLE external_data_cache ADD CONSTRAINT chk_data_source_valid CHECK (
    data_source IN ('CNEP', 'CEIS', 'INTERNAL_RESTRICTIVE', 'PORTAL_TRANSPARENCIA')
);

ALTER TABLE external_data_cache ADD CONSTRAINT chk_expires_after_created CHECK (expires_at > created_at);

-- Create unique constraint to prevent duplicate entries
CREATE UNIQUE INDEX IF NOT EXISTS idx_external_data_cache_unique_active 
ON external_data_cache(document, data_source) 
WHERE is_active = true;

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_external_data_cache_updated_at 
    BEFORE UPDATE ON external_data_cache 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Create api_request_log table for monitoring
CREATE TABLE IF NOT EXISTS api_request_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document VARCHAR(20) NOT NULL,
    data_source VARCHAR(50) NOT NULL,
    request_url VARCHAR(500),
    response_status INTEGER,
    response_time_ms INTEGER,
    error_message TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for api_request_log
CREATE INDEX IF NOT EXISTS idx_api_request_log_document ON api_request_log(document);
CREATE INDEX IF NOT EXISTS idx_api_request_log_data_source ON api_request_log(data_source);
CREATE INDEX IF NOT EXISTS idx_api_request_log_created_at ON api_request_log(created_at);
CREATE INDEX IF NOT EXISTS idx_api_request_log_response_status ON api_request_log(response_status);

-- Create view for cache statistics
CREATE OR REPLACE VIEW cache_statistics AS
SELECT 
    data_source,
    COUNT(*) as total_entries,
    COUNT(CASE WHEN is_active = true THEN 1 END) as active_entries,
    COUNT(CASE WHEN expires_at < CURRENT_TIMESTAMP THEN 1 END) as expired_entries,
    AVG(EXTRACT(EPOCH FROM (expires_at - created_at))/3600) as avg_ttl_hours,
    MAX(last_updated) as last_cache_update,
    MIN(expires_at) as next_expiration
FROM external_data_cache
GROUP BY data_source;

-- Create view for API performance metrics
CREATE OR REPLACE VIEW api_performance_metrics AS
SELECT 
    data_source,
    DATE(created_at) as request_date,
    COUNT(*) as total_requests,
    COUNT(CASE WHEN response_status = 200 THEN 1 END) as successful_requests,
    COUNT(CASE WHEN response_status >= 400 THEN 1 END) as failed_requests,
    AVG(response_time_ms) as avg_response_time_ms,
    MAX(response_time_ms) as max_response_time_ms,
    MIN(response_time_ms) as min_response_time_ms
FROM api_request_log
GROUP BY data_source, DATE(created_at);

-- Create function to clean expired cache entries
CREATE OR REPLACE FUNCTION clean_expired_cache()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    UPDATE external_data_cache 
    SET is_active = false, updated_at = CURRENT_TIMESTAMP
    WHERE expires_at < CURRENT_TIMESTAMP AND is_active = true;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create function to get cached data
CREATE OR REPLACE FUNCTION get_cached_data(
    p_document VARCHAR(20),
    p_data_source VARCHAR(50)
)
RETURNS JSONB AS $$
DECLARE
    cached_data JSONB;
BEGIN
    SELECT response_data INTO cached_data
    FROM external_data_cache
    WHERE document = p_document 
      AND data_source = p_data_source 
      AND is_active = true 
      AND expires_at > CURRENT_TIMESTAMP;
    
    RETURN cached_data;
END;
$$ LANGUAGE plpgsql;

-- Ensure api_user has access to all created objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO api_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO api_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO api_user;

COMMENT ON TABLE external_data_cache IS 'Cache for external API responses to improve performance and reduce API calls';
COMMENT ON TABLE api_request_log IS 'Log of all external API requests for monitoring and analytics';
COMMENT ON VIEW cache_statistics IS 'Statistics about cache usage by data source';
COMMENT ON VIEW api_performance_metrics IS 'Performance metrics for external API calls';
COMMENT ON FUNCTION clean_expired_cache() IS 'Function to mark expired cache entries as inactive';
COMMENT ON FUNCTION get_cached_data(VARCHAR, VARCHAR) IS 'Function to retrieve cached data for a document and source';