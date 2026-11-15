-- Session 1 (FIX: REPEATABLE READ detects the concurrent update and aborts the loser)
\set ON_ERROR_STOP off
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance AS bal FROM account WHERE account_id = 1  \gset
\echo S1: read balance :bal
SELECT pg_sleep(2);   -- simulates application processing time
UPDATE account SET balance = :bal - 1000 WHERE account_id = 1;
\echo S1: UPDATE issued: balance = :bal - 1000
COMMIT;
\echo S1: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
