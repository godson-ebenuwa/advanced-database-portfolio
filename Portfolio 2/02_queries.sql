-- =====================================================================
-- Portfolio 2: benchmark queries (run once BEFORE and once AFTER 03_indexes.sql)
-- Usage: psql -d lagos_trust_bank -f 02_queries.sql > results_before.txt
-- =====================================================================
\timing on

-- Q1: Account statement - last 90 days of ledger entries for one account
-- (the seed data is random, so first pick an account that has recent activity)
SELECT account_id AS busy_acct
FROM account_transaction
WHERE created_at >= NOW() - INTERVAL '90 days'
GROUP BY account_id ORDER BY COUNT(*) DESC, account_id LIMIT 1 \gset

EXPLAIN (ANALYZE, BUFFERS)
SELECT txn_id, txn_type, amount, balance_after, created_at
FROM account_transaction
WHERE account_id = :busy_acct
  AND created_at >= NOW() - INTERVAL '90 days'
ORDER BY created_at DESC;

-- Q2: Customer search by surname and first name (teller lookup)
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, first_name, last_name, phone, email
FROM customer
WHERE last_name = 'Okafor' AND first_name = 'Adaeze';

-- Q3: All accounts owned by a customer, with branch and type (join on FK columns)
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.account_number, t.type_name, b.branch_name, a.balance
FROM account a
JOIN account_type t ON t.type_id = a.type_id
JOIN branch b       ON b.branch_id = a.branch_id
WHERE a.customer_id = 7777;

-- Q4: Failed transfers in the last 90 days with sender account numbers (compliance report)
EXPLAIN (ANALYZE, BUFFERS)
SELECT tr.reference, tr.amount, tr.initiated_at, a.account_number
FROM transfer tr
JOIN account a ON a.account_id = tr.from_account_id
WHERE tr.status = 'FAILED'
  AND tr.initiated_at >= NOW() - INTERVAL '90 days'
ORDER BY tr.initiated_at DESC;

-- Q5: Top 10 customers by total balance (aggregation + join)
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_id, c.first_name, c.last_name, SUM(a.balance) AS total_balance
FROM customer c
JOIN account a ON a.customer_id = c.customer_id
WHERE a.status = 'ACTIVE'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_balance DESC
LIMIT 10;

-- Q6: Monthly transaction volume per type (full-table analytical aggregate)
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', created_at) AS month, txn_type,
       COUNT(*) AS txn_count, SUM(amount) AS total_amount
FROM account_transaction
GROUP BY 1, 2
ORDER BY 1, 2;
