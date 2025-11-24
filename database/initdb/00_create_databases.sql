-- 00_create_databases.sql

-- Create application users first
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'eagle_user') THEN
        CREATE USER eagle_user WITH PASSWORD 'eagle_pass';
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'customer_user') THEN
        CREATE USER customer_user WITH PASSWORD 'customer_pass';
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'alert_user') THEN
        CREATE USER alert_user WITH PASSWORD 'alert_pass';
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'api_user') THEN
        CREATE USER api_user WITH PASSWORD 'api_pass';
    END IF;
END $$;

-- Create databases
SELECT 'CREATE DATABASE ms_customer'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_customer')\gexec

SELECT 'CREATE DATABASE ms_alert'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_alert')\gexec

SELECT 'CREATE DATABASE ms_dailyrountines'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_dailyrountines')\gexec

SELECT 'CREATE DATABASE ms_enrichment'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_enrichment')\gexec

SELECT 'CREATE DATABASE ms_audit'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_audit')\gexec

SELECT 'CREATE DATABASE ms_kys'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_kys')\gexec

SELECT 'CREATE DATABASE ms_dash'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_dash')\gexec

SELECT 'CREATE DATABASE ms_report'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_report')\gexec

SELECT 'CREATE DATABASE ms_api'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_api')\gexec

SELECT 'CREATE DATABASE ms_rules'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_rules')\gexec

SELECT 'CREATE DATABASE ms_transaction'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ms_transaction')\gexec

SELECT 'CREATE DATABASE keycloak'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak')\gexec

SELECT 'CREATE DATABASE ms_orchestrator'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ms_orchestrator')\gexec

SELECT 'CREATE DATABASE ms_qa'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ms_qa')\gexec

SELECT 'CREATE DATABASE ms_qa_test'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ms_qa_test')\gexec

-- Grant permissions to users on their respective databases
GRANT ALL PRIVILEGES ON DATABASE ms_transaction TO eagle_user;
GRANT ALL PRIVILEGES ON DATABASE ms_customer TO customer_user;
GRANT ALL PRIVILEGES ON DATABASE ms_alert TO alert_user;
GRANT ALL PRIVILEGES ON DATABASE ms_api TO api_user;
-- Cr
eate QA user
DO $ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'qa_user') THEN
        CREATE USER qa_user WITH PASSWORD 'qa_pass';
    END IF;
END $;

-- Grant permissions for QA databases
GRANT ALL PRIVILEGES ON DATABASE ms_qa TO qa_user;
GRANT ALL PRIVILEGES ON DATABASE ms_qa_test TO qa_user;