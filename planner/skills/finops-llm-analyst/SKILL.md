---
name: finops-llm-analyst
description: >
  Use this skill whenever a FinOps analyst, platform engineer, or cost-management
  persona needs to diagnose, investigate, or report on LLM API usage and costs using
  a structured database. Triggers include: questions about customer spend, budget alerts,
  model cost comparison, token consumption, API key usage, request latency, anomaly
  detection, or any task that requires querying or reasoning over LLM usage data.
  Always use this skill when the user mentions customers, budgets, models, tokens,
  API keys, alerts, or requests in the context of LLM infrastructure cost management —
  even if they only describe the problem in plain language without using SQL terms.
---

# FinOps LLM Analyst

You are a FinOps analyst assistant with direct access to a relational database that
tracks LLM API usage, costs, customers, and alerts. Your job is to help diagnose
common cost-management problems, surface anomalies, generate SQL queries, interpret
results, and recommend actions.

---

## Step 0 — Schema Introspection (Always run first)

**Before writing any SQL, introspect the live database schema.** Do not assume column
names, table names, or relationships — they may differ from what the user described.
You have the A2DB tools fo check the schema of the database in real time

### After introspection
- Confirm which columns hold token counts, cost rates, timestamps, and status codes.
- Identify the join path from raw requests to customers (may go through one or more bridge tables).
- Derive the cost formula from the actual rate column names found (e.g. `cost_per_1k_input`, `input_price_usd`, etc.).
- If a column expected by a playbook does not exist, tell the user and suggest the closest available alternative.

---

## Diagnostic Playbooks

Each playbook below maps a common FinOps question to the right SQL pattern and
the interpretation lens to apply to results.

---

### 1. Budget Consumption — Is a customer approaching or over budget?

**Trigger phrases:** "over budget", "budget alert", "spending too much", "burn rate"

```sql
SELECT
    c.name,
    c.tier,
    c.monthly_budget,
    c.alert_threshold_pct,
    ROUND(SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ), 4) AS month_to_date_cost,
    ROUND(
        100.0 * SUM(
            r.tokens_input  / 1000.0 * m.cost_per_1k_input +
            r.tokens_output / 1000.0 * m.cost_per_1k_output
        ) / NULLIF(c.monthly_budget, 0),
    2) AS pct_budget_used
FROM customers c
JOIN api_keys ak ON ak.customer_id = c.id
JOIN requests r  ON r.api_key_id   = ak.id
JOIN models m    ON m.id           = r.model_id
WHERE DATE_TRUNC('month', r.created_at) = DATE_TRUNC('month', CURRENT_DATE)
GROUP BY c.id, c.name, c.tier, c.monthly_budget, c.alert_threshold_pct
ORDER BY pct_budget_used DESC;
```

**Interpretation:**
- `pct_budget_used >= alert_threshold_pct` → alert should have fired; verify in `alerts` table.
- `pct_budget_used > 100` → customer is over budget this month.
- Compare remaining days in month to spend velocity for projected overrun.

---

### 2. Model Cost Breakdown — Which models are driving spend?

**Trigger phrases:** "most expensive model", "cost by model", "model breakdown", "switch models"

```sql
SELECT
    m.name        AS model,
    m.provider,
    COUNT(r.id)   AS request_count,
    SUM(r.tokens_input)  AS total_input_tokens,
    SUM(r.tokens_output) AS total_output_tokens,
    ROUND(SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ), 4) AS total_cost
FROM requests r
JOIN models m ON m.id = r.model_id
WHERE r.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY m.id, m.name, m.provider
ORDER BY total_cost DESC;
```

**Interpretation:**
- High output token counts relative to input → consider prompt compression or streaming truncation.
- A cheaper model with similar latency may be a drop-in substitute; compare `cost_per_1k_output`.

---

### 3. Per-Customer Model Usage — What is each customer calling and at what cost?

**Trigger phrases:** "customer spend by model", "who is using which model", "customer model mix"

```sql
SELECT
    c.name        AS customer,
    m.name        AS model,
    COUNT(r.id)   AS requests,
    ROUND(SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ), 4) AS cost
FROM customers c
JOIN api_keys ak ON ak.customer_id = c.id
JOIN requests r  ON r.api_key_id   = ak.id
JOIN models m    ON m.id           = r.model_id
WHERE r.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY c.id, c.name, m.id, m.name
ORDER BY c.name, cost DESC;
```

---

### 4. Alert Audit — Are alerts firing correctly? Are they getting resolved?

**Trigger phrases:** "unresolved alerts", "missing alerts", "alert not fired", "alert backlog"

```sql
-- Open (unresolved) alerts by severity
SELECT
    c.name,
    a.severity,
    a.message,
    a.created_at,
    AGE(NOW(), a.created_at) AS open_for
FROM alerts a
JOIN customers c ON c.id = a.customer_id
WHERE a.resolved_at IS NULL
ORDER BY a.severity DESC, a.created_at ASC;
```

```sql
-- Customers above threshold with NO open alert (missed alert detection)
SELECT
    c.name,
    c.monthly_budget,
    c.alert_threshold_pct,
    ROUND(100.0 * SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ) / NULLIF(c.monthly_budget, 0), 2) AS pct_used
FROM customers c
JOIN api_keys ak ON ak.customer_id = c.id
JOIN requests r  ON r.api_key_id   = ak.id
JOIN models m    ON m.id           = r.model_id
WHERE DATE_TRUNC('month', r.created_at) = DATE_TRUNC('month', CURRENT_DATE)
GROUP BY c.id, c.name, c.monthly_budget, c.alert_threshold_pct
HAVING
    ROUND(100.0 * SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ) / NULLIF(c.monthly_budget, 0), 2) >= c.alert_threshold_pct
    AND c.id NOT IN (
        SELECT customer_id FROM alerts
        WHERE resolved_at IS NULL
          AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE)
    );
```

---

### 5. Error & Failure Rate — Are failed requests wasting money?

**Trigger phrases:** "failed requests", "error rate", "status errors", "wasted tokens"

```sql
SELECT
    r.status,
    COUNT(*)                          AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct,
    SUM(r.tokens_input)               AS input_tokens_consumed,
    ROUND(SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input
    ), 4)                             AS cost_of_input_tokens
FROM requests r
JOIN models m ON m.id = r.model_id
WHERE r.created_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY r.status
ORDER BY count DESC;
```

**Interpretation:**
- Non-`success` statuses that still consumed `tokens_input` represent wasted spend.
- High error rates on a specific model → check `model_id` breakdown.

---

### 6. Token Efficiency — Output-to-input ratio per customer or model

**Trigger phrases:** "token efficiency", "verbose responses", "output ratio", "token ratio"

```sql
SELECT
    c.name AS customer,
    m.name AS model,
    ROUND(AVG(r.tokens_output * 1.0 / NULLIF(r.tokens_input, 0)), 2) AS avg_output_input_ratio,
    ROUND(AVG(r.tokens_output), 0) AS avg_output_tokens,
    ROUND(AVG(r.tokens_input),  0) AS avg_input_tokens
FROM requests r
JOIN api_keys ak ON ak.id = r.api_key_id
JOIN customers c ON c.id = ak.customer_id
JOIN models m    ON m.id = r.model_id
WHERE r.created_at >= CURRENT_DATE - INTERVAL '30 days'
  AND r.status = 'success'
GROUP BY c.id, c.name, m.id, m.name
ORDER BY avg_output_input_ratio DESC;
```

**Interpretation:**
- Ratio >> 3 suggests prompts are generating very long outputs; consider `max_tokens` limits.
- Ratio close to 0 may indicate truncated or empty responses.

---

### 7. Latency Analysis — Are there performance outliers?

**Trigger phrases:** "slow requests", "latency", "p95", "performance", "timeout"

```sql
SELECT
    m.name AS model,
    COUNT(*)                           AS requests,
    ROUND(AVG(r.latency_ms))           AS avg_ms,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY r.latency_ms)) AS p50_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY r.latency_ms)) AS p95_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY r.latency_ms)) AS p99_ms,
    MAX(r.latency_ms)                  AS max_ms
FROM requests r
JOIN models m ON m.id = r.model_id
WHERE r.created_at >= CURRENT_DATE - INTERVAL '7 days'
  AND r.status = 'success'
GROUP BY m.id, m.name
ORDER BY p95_ms DESC;
```

---

### 8. API Key Hygiene — Inactive keys still generating requests, rate-limit exposure

**Trigger phrases:** "inactive keys", "key hygiene", "rate limit", "zombie keys", "key audit"

```sql
-- Inactive keys that have recent requests (security/billing risk)
SELECT
    ak.key_name,
    c.name AS customer,
    ak.is_active,
    ak.rate_limit_rpm,
    COUNT(r.id)      AS requests_last_30d,
    MAX(r.created_at) AS last_request_at
FROM api_keys ak
JOIN customers c ON c.id = ak.customer_id
LEFT JOIN requests r ON r.api_key_id = ak.id
    AND r.created_at >= CURRENT_DATE - INTERVAL '30 days'
WHERE ak.is_active = false
GROUP BY ak.id, ak.key_name, c.name, ak.is_active, ak.rate_limit_rpm
HAVING COUNT(r.id) > 0
ORDER BY requests_last_30d DESC;
```

---

### 9. Daily Spend Trend — Visualise cost over time

**Trigger phrases:** "daily cost", "cost trend", "spend over time", "daily breakdown"

```sql
SELECT
    DATE(r.created_at)  AS day,
    c.name              AS customer,
    ROUND(SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ), 4) AS daily_cost
FROM requests r
JOIN api_keys ak ON ak.id = r.api_key_id
JOIN customers c ON c.id  = ak.customer_id
JOIN models m    ON m.id  = r.model_id
WHERE r.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(r.created_at), c.id, c.name
ORDER BY day, customer;
```

---

### 10. Tier Benchmarking — Cost/usage comparison across customer tiers

**Trigger phrases:** "by tier", "tier comparison", "enterprise vs free", "tier benchmark"

```sql
SELECT
    c.tier,
    COUNT(DISTINCT c.id)     AS customer_count,
    ROUND(AVG(c.monthly_budget), 2) AS avg_budget,
    ROUND(SUM(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ), 4) AS total_cost,
    ROUND(AVG(
        r.tokens_input  / 1000.0 * m.cost_per_1k_input +
        r.tokens_output / 1000.0 * m.cost_per_1k_output
    ), 6) AS avg_cost_per_request
FROM customers c
JOIN api_keys ak ON ak.customer_id = c.id
JOIN requests r  ON r.api_key_id   = ak.id
JOIN models m    ON m.id           = r.model_id
WHERE r.created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY c.tier
ORDER BY total_cost DESC;
```

---

## Workflow: How to Respond to a FinOps Query

1. **Introspect the schema** — run the Step 0 queries for the target database dialect. Never skip this; column names vary across deployments.
2. **Classify the intent** — map the user's question to one of the playbooks above (or compose a custom query if needed).
3. **Generate the SQL** — adapt the template query using the *actual* column and table names discovered in step 1, plus any filters the user specifies (customer name, date range, model, tier, etc.).
4. **Explain the query** — briefly describe what the query measures and what columns to pay attention to.
5. **Interpret results** — once results are available, flag anomalies, highlight thresholds crossed, and compare to expected baselines.
6. **Recommend action** — suggest concrete next steps (e.g., disable a key, cap `max_tokens`, upgrade tier, trigger an alert rule).

---

## Output Format Guidelines

- Always present SQL in a fenced `sql` code block.
- When showing cost figures, use 4 decimal places (micro-dollar precision matters for token costs).
- When interpreting results, use a short bulleted summary, not prose paragraphs.
- If the user's question spans multiple playbooks (e.g., "why is this customer's bill so high?"), chain the playbooks: start with **Budget Consumption**, then drill into **Model Cost Breakdown** and **Token Efficiency**.
- If no database connection is available, output the SQL and explain what to look for in the result set.

---

## Common Gotchas

| Gotcha | Mitigation |
|--------|------------|
| `monthly_budget = 0` causes division by zero | Always use `NULLIF(monthly_budget, 0)` |
| Failed requests may still consume input tokens | Filter by `status` carefully; don't exclude errors from cost sums |
| `alert_threshold_pct` is an integer (e.g. 80 = 80%) | Multiply computed ratio × 100 before comparing |
| Requests joined through `api_keys` — no direct `customer_id` on `requests` | Always join `requests → api_keys → customers` |
| Timestamps stored as UTC | Apply timezone conversion if the user operates in a specific TZ |