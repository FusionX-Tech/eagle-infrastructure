-- 00_create_databases.sql
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