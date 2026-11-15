-- =====================================================================
-- Portfolio 2: bulk test data for performance testing
-- Run AFTER portfolio-1-database-design/schema.sql on a fresh database.
-- Volumes: 20,000 customers | 30,000 accounts | 300,000 ledger rows | 50,000 transfers
-- NOTE: ledger balance_after values are random: this data is for measuring
-- query performance only, not for testing financial correctness.
-- =====================================================================

-- 1. Customers
INSERT INTO customer (first_name, last_name, email, phone, bvn, date_of_birth, address)
SELECT
    (ARRAY['Adaeze','Tunde','Amina','Chinedu','Ngozi','Ibrahim','Funke','Emeka','Zainab','Segun'])[1 + floor(random()*10)::int],
    (ARRAY['Okafor','Bello','Yusuf','Adeyemi','Nwosu','Abubakar','Ogunleye','Eze','Mohammed','Balogun',
           'Ibe','Salami','Danjuma','Okonkwo','Lawal'])[1 + floor(random()*15)::int],
    'user' || g || '@example.com',
    '09' || lpad(g::text, 9, '0'),
    lpad((100000000 + g)::text, 11, '0'),
    DATE '1960-01-01' + (random() * 15000)::int,
    'Street ' || g || ', Lagos'
FROM generate_series(1, 20000) AS g;

-- 2. Accounts (about 1.5 per customer)
WITH c AS (
    SELECT customer_id, row_number() OVER (ORDER BY customer_id) AS rn FROM customer
), n AS (SELECT count(*) AS total FROM customer)
INSERT INTO account (account_number, customer_id, branch_id, type_id, balance, status, opened_at)
SELECT
    lpad((1000000000 + g)::text, 10, '0'),
    c.customer_id,
    1 + (g % 3),
    1 + (g % 3),
    round((random() * 5000000)::numeric, 2),
    (ARRAY['ACTIVE','ACTIVE','ACTIVE','ACTIVE','DORMANT','FROZEN'])[1 + floor(random()*6)::int],
    NOW() - (random() * 1000 || ' days')::interval
FROM generate_series(1, 30000) AS g
JOIN n ON TRUE
JOIN c ON c.rn = ((g - 1) % n.total) + 1;

-- 3. Transfers
INSERT INTO transfer (reference, from_account_id, to_account_id, amount, status, initiated_at)
SELECT
    'TRF' || lpad(s.g::text, 10, '0'),
    s.f,
    ((s.f - 1 + 1 + s.off) % s.n) + 1,           -- guaranteed different from s.f
    round((random() * 500000 + 100)::numeric, 2),
    (ARRAY['SUCCESS','SUCCESS','SUCCESS','SUCCESS','SUCCESS','SUCCESS','SUCCESS','SUCCESS','FAILED','REVERSED'])
        [1 + floor(random()*10)::int],
    NOW() - (random() * 365 || ' days')::interval
FROM (
    SELECT g,
           (SELECT max(account_id) FROM account) AS n,
           1 + floor(random() * (SELECT max(account_id) FROM account))::int AS f,
           floor(random() * ((SELECT max(account_id) FROM account) - 1))::int AS off
    FROM generate_series(1, 50000) AS g
) s;

-- 4. Ledger transactions
INSERT INTO account_transaction (account_id, txn_type, amount, balance_after, description, created_at)
SELECT
    1 + floor(random() * (SELECT max(account_id) FROM account))::int,
    (ARRAY['DEPOSIT','WITHDRAWAL','DEPOSIT','WITHDRAWAL','DEPOSIT'])[1 + floor(random()*5)::int],
    round((random() * 200000 + 100)::numeric, 2),
    round((random() * 5000000)::numeric, 2),
    'Auto-generated txn ' || g,
    NOW() - (random() * 365 || ' days')::interval
FROM generate_series(1, 300000) AS g;

-- 5. Refresh planner statistics (important before measuring plans)
ANALYZE;

SELECT 'customer' AS tbl, count(*) FROM customer
UNION ALL SELECT 'account', count(*) FROM account
UNION ALL SELECT 'transfer', count(*) FROM transfer
UNION ALL SELECT 'account_transaction', count(*) FROM account_transaction;
