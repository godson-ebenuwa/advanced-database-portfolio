-- Session 2: withdraw 2000 from account 1 using read-modify-write (how many apps do it)
\set ON_ERROR_STOP off
BEGIN;
SELECT balance AS bal FROM account WHERE account_id = 1  \gset
\echo S2: read balance :bal
SELECT pg_sleep(3);   -- simulates application processing time
UPDATE account SET balance = :bal - 2000 WHERE account_id = 1;
\echo S2: UPDATE issued: balance = :bal - 2000
COMMIT;
\echo S2: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
