-- ============================================
-- AI Platform Operations Agent — Schema + Data
-- ============================================

DROP TABLE IF EXISTS requests CASCADE;
DROP TABLE IF EXISTS alerts CASCADE;
DROP TABLE IF EXISTS api_keys CASCADE;
DROP TABLE IF EXISTS models CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- ============================================
-- 1. CUSTOMERS
-- ============================================
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    tier VARCHAR(20) CHECK (tier IN ('free', 'pro', 'enterprise')),
    monthly_budget DECIMAL(10,2),
    alert_threshold_pct INT DEFAULT 80,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO customers (name, tier, monthly_budget, alert_threshold_pct, created_at) VALUES
('Acme Corp', 'enterprise', 5000.00, 75, '2024-06-01'),
('StartupXYZ', 'pro', 500.00, 80, '2024-08-15'),
('DevShop', 'pro', 300.00, 90, '2024-09-01'),
('Hobbyist_Alice', 'free', 50.00, 100, '2025-01-10'),
('MegaScale AI', 'enterprise', 20000.00, 60, '2024-03-01'),
('Lambda Labs', 'enterprise', 8000.00, 70, '2024-05-20'),
('IndieDev_Bob', 'free', 50.00, 100, '2025-02-01'),
('CodeCraft Studio', 'pro', 750.00, 85, '2024-07-10'),
('DataWiz Inc', 'enterprise', 12000.00, 65, '2024-04-01'),
('SideProject_Carol', 'free', 50.00, 100, '2025-03-01');

-- ============================================
-- 2. MODELS
-- ============================================
CREATE TABLE models (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    provider VARCHAR(50),
    region VARCHAR(20),
    cost_per_1k_input DECIMAL(8,6),
    cost_per_1k_output DECIMAL(8,6)
);

INSERT INTO models (name, provider, region, cost_per_1k_input, cost_per_1k_output) VALUES
('gpt-4o', 'OpenAI', 'us-east', 0.005000, 0.015000),
('gpt-4o-mini', 'OpenAI', 'us-east', 0.000150, 0.000600),
('claude-3-7-sonnet', 'Anthropic', 'us-west', 0.003000, 0.015000),
('claude-3-5-haiku', 'Anthropic', 'us-west', 0.000800, 0.004000),
('gemini-2.0-flash', 'Google', 'us-central', 0.000500, 0.001500),
('gemini-2.0-pro', 'Google', 'us-central', 0.003500, 0.010500),
('llama-3.3-70b', 'Meta', 'eu-west', 0.000900, 0.000900),
('mistral-large', 'Mistral', 'eu-central', 0.002000, 0.006000),
('deepseek-v3', 'DeepSeek', 'ap-south', 0.000270, 0.001100),
('qwen-2.5-72b', 'Alibaba', 'ap-east', 0.001200, 0.001200);

-- ============================================
-- 3. API KEYS
-- ============================================
CREATE TABLE api_keys (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    key_name VARCHAR(100),
    is_active BOOLEAN DEFAULT true,
    rate_limit_rpm INT DEFAULT 60,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO api_keys (customer_id, key_name, is_active, rate_limit_rpm, created_at) VALUES
(1, 'acme-prod', true, 10000, '2024-06-01'),
(1, 'acme-staging', true, 1000, '2024-06-01'),
(1, 'acme-dev', true, 500, '2024-06-15'),
(2, 'startup-prod', true, 2000, '2024-08-15'),
(2, 'startup-dev', true, 300, '2024-09-01'),
(3, 'devshop-main', true, 1500, '2024-09-01'),
(4, 'alice-playground', true, 60, '2025-01-10'),
(5, 'megascale-prod', true, 50000, '2024-03-01'),
(5, 'megascale-batch', true, 10000, '2024-03-01'),
(5, 'megascale-test', false, 5000, '2024-03-01'),  -- inactive key
(6, 'lambda-prod', true, 15000, '2024-05-20'),
(6, 'lambda-research', true, 3000, '2024-06-01'),
(7, 'bob-sideproject', true, 60, '2025-02-01'),
(8, 'codecraft-prod', true, 3000, '2024-07-10'),
(8, 'codecraft-internal', true, 500, '2024-08-01'),
(9, 'datawiz-prod', true, 20000, '2024-04-01'),
(9, 'datawiz-etl', true, 5000, '2024-05-01'),
(10, 'carol-experiment', true, 60, '2025-03-01');

-- ============================================
-- 4. REQUESTS
-- ============================================
CREATE TABLE requests (
    id SERIAL PRIMARY KEY,
    api_key_id INT REFERENCES api_keys(id),
    model_id INT REFERENCES models(id),
    tokens_input INT,
    tokens_output INT,
    latency_ms INT,
    status VARCHAR(20) CHECK (status IN ('success', 'rate_limited', 'timeout', 'error')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Generate requests for a specific key/model with weighted distributions
INSERT INTO requests (api_key_id, model_id, tokens_input, tokens_output, latency_ms, status, created_at)
SELECT 
    key_model.key_id,
    key_model.model_id,
    key_model.tokens_input,
    key_model.tokens_output,
    key_model.latency_ms,
    key_model.status,
    key_model.created_at
FROM (
    -- Acme Corp (enterprise, heavy usage, near budget)
    SELECT 1 AS key_id, 1 AS model_id, 2500 AS tokens_input, 800 AS tokens_output, 420 AS latency_ms, 'success'::varchar AS status, NOW() - (random() * INTERVAL '25 days') AS created_at FROM generate_series(1, 800)
    UNION ALL SELECT 1, 3, 3000, 1200, 680, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 600)
    UNION ALL SELECT 1, 5, 1500, 400, 180, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 1200)
    UNION ALL SELECT 1, 1, 2500, 800, 420, 'rate_limited', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 45)
    UNION ALL SELECT 1, 3, 3000, 1200, 30000, 'timeout', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 12)
    UNION ALL SELECT 2, 1, 800, 300, 380, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 150)
    UNION ALL SELECT 2, 5, 600, 200, 150, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 200)
    
    -- StartupXYZ (pro, moderate usage)
    UNION ALL SELECT 4, 2, 400, 150, 120, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 900)
    UNION ALL SELECT 4, 5, 500, 180, 140, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 700)
    UNION ALL SELECT 4, 2, 400, 150, 120, 'error', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 25)
    UNION ALL SELECT 5, 2, 300, 100, 110, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 300)
    
    -- DevShop (pro, small but consistent)
    UNION ALL SELECT 6, 4, 350, 120, 200, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 500)
    UNION ALL SELECT 6, 2, 400, 150, 115, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 400)
    UNION ALL SELECT 6, 4, 350, 120, 200, 'rate_limited', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 15)
    
    -- Hobbyist_Alice (free, tiny usage)
    UNION ALL SELECT 7, 2, 200, 80, 105, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 80)
    UNION ALL SELECT 7, 5, 250, 90, 130, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 60)
    
    -- MegaScale AI (enterprise, MASSIVE usage — should be well within budget)
    UNION ALL SELECT 9, 1, 4000, 1500, 450, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 5000)
    UNION ALL SELECT 9, 3, 3500, 1400, 700, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 4000)
    UNION ALL SELECT 9, 6, 5000, 2000, 520, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 3000)
    UNION ALL SELECT 9, 9, 6000, 2500, 280, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 2500)
    UNION ALL SELECT 9, 1, 4000, 1500, 450, 'rate_limited', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 180)
    UNION ALL SELECT 9, 3, 3500, 1400, 700, 'timeout', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 40)
    UNION ALL SELECT 10, 9, 8000, 3000, 290, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 1500)
    UNION ALL SELECT 10, 6, 6000, 2200, 510, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 1200)
    
    -- Lambda Labs (enterprise, heavy)
    UNION ALL SELECT 11, 3, 2800, 1000, 650, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 1500)
    UNION ALL SELECT 11, 7, 3200, 1100, 350, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 2000)
    UNION ALL SELECT 11, 3, 2800, 1000, 650, 'error', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 30)
    UNION ALL SELECT 12, 7, 2500, 900, 340, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 800)
    UNION ALL SELECT 12, 8, 3000, 1000, 400, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 600)
    
    -- IndieDev_Bob (free)
    UNION ALL SELECT 13, 2, 180, 70, 108, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 50)
    UNION ALL SELECT 13, 5, 200, 80, 125, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 40)
    
    -- CodeCraft Studio (pro)
    UNION ALL SELECT 14, 4, 500, 200, 195, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 600)
    UNION ALL SELECT 14, 2, 450, 170, 118, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 500)
    UNION ALL SELECT 15, 4, 400, 150, 190, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 200)
    
    -- DataWiz Inc (enterprise)
    UNION ALL SELECT 16, 1, 3500, 1300, 430, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 2500)
    UNION ALL SELECT 16, 6, 4500, 1800, 530, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 1800)
    UNION ALL SELECT 16, 10, 5000, 2000, 380, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 1500)
    UNION ALL SELECT 17, 6, 4000, 1600, 525, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 900)
    UNION ALL SELECT 17, 10, 4500, 1900, 375, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 800)
    
    -- SideProject_Carol (free)
    UNION ALL SELECT 18, 2, 150, 60, 102, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 30)
    UNION ALL SELECT 18, 5, 180, 70, 128, 'success', NOW() - (random() * INTERVAL '25 days') FROM generate_series(1, 25)
    
) key_model;

-- ============================================
-- 5. ALERTS
-- ============================================
CREATE TABLE alerts (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    severity VARCHAR(20) CHECK (severity IN ('info', 'warning', 'critical')),
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

INSERT INTO alerts (customer_id, severity, message, created_at, resolved_at) VALUES
(2, 'warning', 'StartupXYZ reached 82% of monthly budget', NOW() - INTERVAL '2 days', NULL),
(3, 'info', 'DevShop API key rotated successfully', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days'),
(5, 'critical', 'MegaScale AI experiencing elevated timeout rate on claude-3-7-sonnet', NOW() - INTERVAL '6 hours', NULL),
(1, 'warning', 'Acme Corp rate limit hits increased 3x in last 24h', NOW() - INTERVAL '1 day', NULL),
(6, 'info', 'Lambda Labs new model deployment completed', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days');

-- ============================================
-- 6. INDEXES
-- ============================================
CREATE INDEX idx_requests_created_at ON requests(created_at);
CREATE INDEX idx_requests_api_key_id ON requests(api_key_id);
CREATE INDEX idx_requests_model_id ON requests(model_id);
CREATE INDEX idx_requests_status ON requests(status);
CREATE INDEX idx_alerts_customer_id ON alerts(customer_id);
CREATE INDEX idx_alerts_created_at ON alerts(created_at);