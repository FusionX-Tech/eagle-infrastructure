-- 03_ms_transaction_schema.sql
\c ms_transaction;

-- Grant schema permissions to eagle_user
GRANT ALL ON SCHEMA public TO eagle_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO eagle_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO eagle_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO eagle_user;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO eagle_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO eagle_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO eagle_user;

-- Create transactions table
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_document VARCHAR(20) NOT NULL,
    counterparty_document VARCHAR(20),
    counterparty_name VARCHAR(255),
    amount DECIMAL(15,2) NOT NULL,
    type VARCHAR(20) NOT NULL,
    transaction_date TIMESTAMP NOT NULL,
    description VARCHAR(500),
    channel VARCHAR(50),
    source_system VARCHAR(100),
    transaction_id VARCHAR(50),
    account_number VARCHAR(20),
    branch_code VARCHAR(10),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_transactions_customer_document ON transactions(customer_document);
CREATE INDEX IF NOT EXISTS idx_transactions_transaction_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_customer_date ON transactions(customer_document, transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_counterparty_document ON transactions(counterparty_document);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_amount ON transactions(amount);
CREATE INDEX IF NOT EXISTS idx_transactions_channel ON transactions(channel);

-- Create composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_transactions_customer_date_type ON transactions(customer_document, transaction_date, type);
CREATE INDEX IF NOT EXISTS idx_transactions_customer_counterparty ON transactions(customer_document, counterparty_document);

-- Create partial indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_transactions_large_amounts ON transactions(customer_document, amount) 
WHERE amount > 10000;

-- Removed problematic partial index with non-immutable function
-- CREATE INDEX IF NOT EXISTS idx_transactions_recent ON transactions(customer_document, transaction_date) 
-- WHERE transaction_date >= CURRENT_DATE - INTERVAL '1 year';

-- Add constraints
ALTER TABLE transactions ADD CONSTRAINT chk_amount_positive CHECK (amount > 0);
ALTER TABLE transactions ADD CONSTRAINT chk_transaction_type CHECK (
    type IN ('CREDIT', 'DEBIT', 'TRANSFER_IN', 'TRANSFER_OUT', 'PAYMENT', 'DEPOSIT', 
             'WITHDRAWAL', 'PIX_IN', 'PIX_OUT', 'TED_IN', 'TED_OUT', 'DOC_IN', 'DOC_OUT')
);

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_transactions_updated_at 
    BEFORE UPDATE ON transactions 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Create view for transaction summaries
CREATE OR REPLACE VIEW transaction_summaries AS
SELECT 
    customer_document,
    DATE(transaction_date) as transaction_day,
    COUNT(*) as transaction_count,
    SUM(amount) as total_amount,
    AVG(amount) as average_amount,
    MAX(amount) as max_amount,
    MIN(amount) as min_amount,
    COUNT(DISTINCT counterparty_document) as unique_counterparties
FROM transactions
GROUP BY customer_document, DATE(transaction_date);

-- Create view for monthly KPIs
CREATE OR REPLACE VIEW monthly_transaction_kpis AS
SELECT 
    customer_document,
    DATE_TRUNC('month', transaction_date) as month,
    COUNT(*) as transaction_count,
    SUM(amount) as total_volume,
    AVG(amount) as average_amount,
    MAX(amount) as largest_transaction,
    MIN(amount) as smallest_transaction,
    COUNT(DISTINCT counterparty_document) as unique_counterparties,
    SUM(CASE WHEN type IN ('CREDIT', 'TRANSFER_IN', 'DEPOSIT', 'PIX_IN', 'TED_IN', 'DOC_IN') THEN amount ELSE 0 END) as incoming_volume,
    SUM(CASE WHEN type IN ('DEBIT', 'TRANSFER_OUT', 'PAYMENT', 'WITHDRAWAL', 'PIX_OUT', 'TED_OUT', 'DOC_OUT') THEN amount ELSE 0 END) as outgoing_volume,
    COUNT(CASE WHEN type IN ('CREDIT', 'TRANSFER_IN', 'DEPOSIT', 'PIX_IN', 'TED_IN', 'DOC_IN') THEN 1 END) as incoming_count,
    COUNT(CASE WHEN type IN ('DEBIT', 'TRANSFER_OUT', 'PAYMENT', 'WITHDRAWAL', 'PIX_OUT', 'TED_OUT', 'DOC_OUT') THEN 1 END) as outgoing_count
FROM transactions
GROUP BY customer_document, DATE_TRUNC('month', transaction_date);

COMMENT ON TABLE transactions IS 'Stores all customer transactions for analysis and KPI calculation';
COMMENT ON VIEW transaction_summaries IS 'Daily transaction summaries by customer';
COMMENT ON VIEW monthly_transaction_kpis IS 'Monthly KPIs and metrics by customer';

-- Ensure eagle_user has access to all created objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO eagle_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO eagle_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO eagle_user;