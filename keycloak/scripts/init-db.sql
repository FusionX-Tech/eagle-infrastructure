-- Keycloak Database Initialization Script
-- This script sets up the initial database configuration for Keycloak

-- Create additional schemas if needed
-- CREATE SCHEMA IF NOT EXISTS keycloak_audit;

-- Set up database parameters for optimal Keycloak performance
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;

-- Reload configuration
SELECT pg_reload_conf();

-- Create indexes for better performance (these will be created by Keycloak, but we can prepare)
-- Note: Keycloak will create its own tables and indexes, this is just for reference

-- Log the initialization
DO $$
BEGIN
    RAISE NOTICE 'Keycloak database initialized successfully';
    RAISE NOTICE 'Database: %', current_database();
    RAISE NOTICE 'User: %', current_user;
    RAISE NOTICE 'Timestamp: %', now();
END $$;