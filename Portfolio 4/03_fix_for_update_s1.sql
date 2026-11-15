-- Session 1 (FIX: SELECT ... FOR UPDATE locks the row until COMMIT)
\set ON_ERROR_STOP off
BEGIN;
SELECT balance AS bal FROM account WHERE account_id = 1 FOR UPDATE \gset
\echo S1: read balance :bal
SELECT pg_sleep(2);   -- simulates application processing time
UPDATE account SET balance = :bal - 1000 WHERE account_id = 1;
\echo S1: UPDATE issued: balance = :bal - 1000
COMMIT;
\echo S1: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
