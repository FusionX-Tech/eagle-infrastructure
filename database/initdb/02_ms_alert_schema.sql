\connect ms_alert;

-- 1) Schema e search_path (somente para esta sessão)
CREATE SCHEMA IF NOT EXISTS ms_alert AUTHORIZATION CURRENT_USER;
SET search_path TO ms_alert, public;

-- 2) Extensão UUID neste DB
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 3) Tabela principal de alertas
CREATE TABLE IF NOT EXISTS ms_alert.alerts (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_document   text NOT NULL,                    -- documento do cliente (CPF/CNPJ)
  scope_start_date    date NOT NULL,                    -- data de início do escopo de análise
  scope_end_date      date NOT NULL,                    -- data de fim do escopo de análise
  status              text NOT NULL DEFAULT 'CREATED', -- CREATED|ENRICHING|ENRICHED|COMPLETED|FAILED
  process_id          text,                             -- ID do processo de orquestração
  enrichment_data     jsonb DEFAULT '{}'::jsonb,        -- dados de enriquecimento coletados
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- 4) Índices otimizados para o novo modelo
CREATE INDEX IF NOT EXISTS ix_alerts_time
  ON ms_alert.alerts (created_at DESC);

CREATE INDEX IF NOT EXISTS ix_alerts_status
  ON ms_alert.alerts (status);

CREATE INDEX IF NOT EXISTS ix_alerts_customer_document
  ON ms_alert.alerts (customer_document);

CREATE INDEX IF NOT EXISTS ix_alerts_process_id
  ON ms_alert.alerts (process_id);

CREATE INDEX IF NOT EXISTS ix_alerts_customer_status
  ON ms_alert.alerts (customer_document, status);

CREATE INDEX IF NOT EXISTS ix_alerts_scope_dates
  ON ms_alert.alerts (scope_start_date, scope_end_date);

-- 5) Tabela de transações do alerta
CREATE TABLE IF NOT EXISTS ms_alert.alert_tx (
  id            bigserial PRIMARY KEY,
  alert_id      uuid NOT NULL REFERENCES ms_alert.alerts(id) ON DELETE CASCADE,
  tx_id         text NOT NULL,
  tx_time       timestamptz NOT NULL,
  amount        numeric(18,2) NOT NULL,
  currency      char(3) NOT NULL,
  direction     text NOT NULL,             -- IN|OUT
  counterparty  jsonb NOT NULL,
  channel       text,
  meta          jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS ix_alert_tx_alert_time
  ON ms_alert.alert_tx (alert_id, tx_time DESC);

-- 6) Entidades vinculadas ao alerta
CREATE TABLE IF NOT EXISTS ms_alert.alert_entities (
  id            bigserial PRIMARY KEY,
  alert_id      uuid NOT NULL REFERENCES ms_alert.alerts(id) ON DELETE CASCADE,
  entity_type   text NOT NULL,             -- DEVICE|ADDR|DOC|ACCOUNT|IP...
  entity_key    text NOT NULL,
  details       jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS ix_alert_entities_alert
  ON ms_alert.alert_entities (alert_id, entity_type);

-- 7) Features do alerta
CREATE TABLE IF NOT EXISTS ms_alert.alert_features (
  id            bigserial PRIMARY KEY,
  alert_id      uuid NOT NULL REFERENCES ms_alert.alerts(id) ON DELETE CASCADE,
  name          text NOT NULL,
  value_num     numeric(20,6),
  value_text    text,
  value_json    jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_alert_features_alert_name
  ON ms_alert.alert_features (alert_id, name);

-- 8) Artefatos/vínculos S3
CREATE TABLE IF NOT EXISTS ms_alert.alert_artifacts (
  id              bigserial PRIMARY KEY,
  alert_id        uuid NOT NULL REFERENCES ms_alert.alerts(id) ON DELETE CASCADE,
  artifact_type   text NOT NULL,        -- ENRICH_PACKAGE|SCREENSHOT|DOC
  s3_uri          text NOT NULL,
  checksum_sha256 text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- 9) Função + trigger de updated_at (qualificadas)
CREATE OR REPLACE FUNCTION ms_alert.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trig_alerts_updated_at ON ms_alert.alerts;

CREATE TRIGGER trig_alerts_updated_at
BEFORE UPDATE ON ms_alert.alerts
FOR EACH ROW
EXECUTE FUNCTION ms_alert.set_updated_at();
