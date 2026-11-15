-- Session 2 (FIX: blocks on FOR UPDATE until Session 1 commits, then reads the NEW balance)
\set ON_ERROR_STOP off
SELECT pg_sleep(0.5);  -- let Session 1 take its lock first
BEGIN;
SELECT balance AS bal FROM account WHERE account_id = 1 FOR UPDATE \gset
\echo S2: read balance :bal
SELECT pg_sleep(0);   -- simulates application processing time
UPDATE account SET balance = :bal - 2000 WHERE account_id = 1;
\echo S2: UPDATE issued: balance = :bal - 2000
COMMIT;
\echo S2: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
