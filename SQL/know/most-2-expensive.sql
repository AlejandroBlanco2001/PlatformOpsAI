SELECT
    r.id AS request_id,
    (
        (r.tokens_input / 1000.0) * m.cost_per_1k_input +
        (r.tokens_output / 1000.0) * m.cost_per_1k_output
    ) AS request_cost
FROM requests r
JOIN api_keys ak ON r.api_key_id = ak.id
JOIN customers c ON ak.customer_id = c.id
JOIN models m ON r.model_id = m.id
WHERE c.name = 'Acme Corp'
ORDER BY request_cost DESC
LIMIT 2;