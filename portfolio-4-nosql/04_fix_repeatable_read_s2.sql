-- Session 2 (REPEATABLE READ: expect "could not serialize access due to concurrent update")
\set ON_ERROR_STOP off
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance AS bal FROM account WHERE account_id = 1  \gset
\echo S2: read balance :bal
SELECT pg_sleep(3);   -- simulates application processing time
UPDATE account SET balance = :bal - 2000 WHERE account_id = 1;
\echo S2: UPDATE issued: balance = :bal - 2000
COMMIT;
\echo S2: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
