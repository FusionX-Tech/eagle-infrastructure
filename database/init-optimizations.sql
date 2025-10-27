-- =====================================================
-- SCRIPT DE INICIALIZAÇÃO DAS OTIMIZAÇÕES DE BANCO
-- =====================================================

-- Criar usuário de replicação
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator WITH REPLICATION PASSWORD 'repl_password' LOGIN;
    END IF;
END
$$;

-- Criar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- Configurar pg_stat_statements
SELECT pg_stat_statements_reset();

-- Criar schemas se não existirem
CREATE SCHEMA IF NOT EXISTS ms_alert;
CREATE SCHEMA IF NOT EXISTS ms_customer;
CREATE SCHEMA IF NOT EXISTS ms_transaction;
CREATE SCHEMA IF NOT EXISTS ms_api;
CREATE SCHEMA IF NOT EXISTS ms_enrichment;
CREATE SCHEMA IF NOT EXISTS ms_orchestrator;

-- Configurar search_path padrão
ALTER DATABASE ms_alert SET search_path TO ms_alert, public;
ALTER DATABASE ms_customer SET search_path TO ms_customer, public;
ALTER DATABASE ms_transaction SET search_path TO ms_transaction, public;

-- Criar função para monitoramento de performance
CREATE OR REPLACE FUNCTION get_database_performance_stats()
RETURNS TABLE (
    database_name TEXT,
    total_connections INTEGER,
    active_connections INTEGER,
    idle_connections INTEGER,
    transactions_per_second NUMERIC,
    cache_hit_ratio NUMERIC,
    index_usage_ratio NUMERIC,
    avg_query_time_ms NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        datname::TEXT as database_name,
        numbackends as total_connections,
        (SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND datname = d.datname)::INTEGER as active_connections,
        (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle' AND datname = d.datname)::INTEGER as idle_connections,
        ROUND((xact_commit + xact_rollback)::NUMERIC / EXTRACT(EPOCH FROM (now() - stats_reset)), 2) as transactions_per_second,
        ROUND(
            CASE 
                WHEN blks_hit + blks_read > 0 
                THEN (blks_hit::NUMERIC / (blks_hit + blks_read)) * 100 
                ELSE 0 
            END, 2
        ) as cache_hit_ratio,
        ROUND(
            CASE 
                WHEN seq_scan + idx_scan > 0 
                THEN (idx_scan::NUMERIC / (seq_scan + idx_scan)) * 100 
                ELSE 0 
            END, 2
        ) as index_usage_ratio,
        COALESCE(
            (SELECT ROUND(mean_exec_time, 2) 
             FROM pg_stat_statements 
             WHERE dbid = d.oid 
             ORDER BY calls DESC 
             LIMIT 1), 0
        ) as avg_query_time_ms
    FROM pg_stat_database d
    WHERE datname NOT IN ('template0', 'template1', 'postgres')
    ORDER BY datname;
END;
$$ LANGUAGE plpgsql;

-- Criar função para análise de queries lentas
CREATE OR REPLACE FUNCTION get_slow_queries(min_duration_ms INTEGER DEFAULT 1000)
RETURNS TABLE (
    query_text TEXT,
    calls BIGINT,
    total_time_ms NUMERIC,
    mean_time_ms NUMERIC,
    max_time_ms NUMERIC,
    rows_affected BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        LEFT(pss.query, 200) as query_text,
        pss.calls,
        ROUND(pss.total_exec_time, 2) as total_time_ms,
        ROUND(pss.mean_exec_time, 2) as mean_time_ms,
        ROUND(pss.max_exec_time, 2) as max_time_ms,
        pss.rows as rows_affected
    FROM pg_stat_statements pss
    WHERE pss.mean_exec_time > min_duration_ms
    ORDER BY pss.mean_exec_time DESC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;

-- Criar função para análise de índices não utilizados
CREATE OR REPLACE FUNCTION get_unused_indexes()
RETURNS TABLE (
    schema_name TEXT,
    table_name TEXT,
    index_name TEXT,
    index_size TEXT,
    scans BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        schemaname::TEXT,
        tablename::TEXT,
        indexname::TEXT,
        pg_size_pretty(pg_relation_size(indexrelid))::TEXT as index_size,
        idx_scan
    FROM pg_stat_user_indexes
    WHERE idx_scan < 10  -- Índices com menos de 10 scans
    AND schemaname NOT IN ('information_schema', 'pg_catalog')
    ORDER BY pg_relation_size(indexrelid) DESC;
END;
$$ LANGUAGE plpgsql;

-- Criar função para manutenção automática
CREATE OR REPLACE FUNCTION perform_maintenance()
RETURNS TEXT AS $$
DECLARE
    maintenance_log TEXT := '';
    table_record RECORD;
BEGIN
    maintenance_log := 'Maintenance started at ' || now() || E'\n';
    
    -- Atualizar estatísticas para tabelas grandes
    FOR table_record IN
        SELECT schemaname, tablename
        FROM pg_stat_user_tables
        WHERE n_tup_ins + n_tup_upd + n_tup_del > 1000
        AND last_analyze < now() - interval '1 day'
    LOOP
        EXECUTE format('ANALYZE %I.%I', table_record.schemaname, table_record.tablename);
        maintenance_log := maintenance_log || 'Analyzed ' || table_record.schemaname || '.' || table_record.tablename || E'\n';
    END LOOP;
    
    -- Executar VACUUM em tabelas com muitos dead tuples
    FOR table_record IN
        SELECT schemaname, tablename, n_dead_tup, n_tup_ins + n_tup_upd + n_tup_del as total_ops
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 1000
        AND n_dead_tup::FLOAT / NULLIF(n_tup_ins + n_tup_upd + n_tup_del, 0) > 0.1
    LOOP
        EXECUTE format('VACUUM %I.%I', table_record.schemaname, table_record.tablename);
        maintenance_log := maintenance_log || 'Vacuumed ' || table_record.schemaname || '.' || table_record.tablename || 
                          ' (dead tuples: ' || table_record.n_dead_tup || ')' || E'\n';
    END LOOP;
    
    -- Reindexar índices fragmentados (se necessário)
    maintenance_log := maintenance_log || 'Maintenance completed at ' || now();
    
    RETURN maintenance_log;
END;
$$ LANGUAGE plpgsql;

-- Criar job de manutenção (se pg_cron estiver disponível)
-- SELECT cron.schedule('database-maintenance', '0 2 * * *', 'SELECT perform_maintenance();');

-- Configurar alertas para métricas críticas
CREATE OR REPLACE FUNCTION check_database_health()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    value NUMERIC,
    threshold NUMERIC,
    message TEXT
) AS $$
BEGIN
    -- Verificar cache hit ratio
    RETURN QUERY
    SELECT 
        'cache_hit_ratio'::TEXT,
        CASE WHEN cache_hit_ratio >= 95 THEN 'OK' ELSE 'WARNING' END::TEXT,
        cache_hit_ratio,
        95::NUMERIC,
        CASE 
            WHEN cache_hit_ratio >= 95 THEN 'Cache hit ratio is healthy'
            ELSE 'Cache hit ratio is below 95%'
        END::TEXT
    FROM get_database_performance_stats()
    WHERE database_name = current_database();
    
    -- Verificar conexões ativas
    RETURN QUERY
    SELECT 
        'active_connections'::TEXT,
        CASE WHEN active_connections <= 150 THEN 'OK' ELSE 'WARNING' END::TEXT,
        active_connections::NUMERIC,
        150::NUMERIC,
        CASE 
            WHEN active_connections <= 150 THEN 'Connection count is normal'
            ELSE 'High number of active connections'
        END::TEXT
    FROM get_database_performance_stats()
    WHERE database_name = current_database();
    
    -- Verificar queries lentas
    RETURN QUERY
    SELECT 
        'slow_queries'::TEXT,
        CASE WHEN COUNT(*) <= 5 THEN 'OK' ELSE 'WARNING' END::TEXT,
        COUNT(*)::NUMERIC,
        5::NUMERIC,
        CASE 
            WHEN COUNT(*) <= 5 THEN 'Slow query count is acceptable'
            ELSE 'Too many slow queries detected'
        END::TEXT
    FROM get_slow_queries(2000);
END;
$$ LANGUAGE plpgsql;

-- Comentários para documentação
COMMENT ON FUNCTION get_database_performance_stats() IS 'Retorna estatísticas de performance do banco de dados';
COMMENT ON FUNCTION get_slow_queries(INTEGER) IS 'Retorna queries lentas acima do threshold especificado';
COMMENT ON FUNCTION get_unused_indexes() IS 'Retorna índices que não estão sendo utilizados';
COMMENT ON FUNCTION perform_maintenance() IS 'Executa manutenção automática do banco (ANALYZE, VACUUM)';
COMMENT ON FUNCTION check_database_health() IS 'Verifica saúde geral do banco de dados';

-- Log de inicialização
INSERT INTO pg_stat_statements_info (dealloc) VALUES (0) ON CONFLICT DO NOTHING;

-- Mensagem de conclusão
DO $$
BEGIN
    RAISE NOTICE 'Database optimizations initialized successfully!';
    RAISE NOTICE 'Available functions:';
    RAISE NOTICE '  - get_database_performance_stats()';
    RAISE NOTICE '  - get_slow_queries(min_duration_ms)';
    RAISE NOTICE '  - get_unused_indexes()';
    RAISE NOTICE '  - perform_maintenance()';
    RAISE NOTICE '  - check_database_health()';
END $$;