-- Session 2: transfer 50 from account 2 -> 1. Locks account 2 FIRST, then account 1 (opposite order!)
\set ON_ERROR_STOP off
BEGIN;
UPDATE account SET balance = balance - 50 WHERE account_id = 2;
\echo S2: locked account 2
SELECT pg_sleep(2);
UPDATE account SET balance = balance + 50 WHERE account_id = 1;
\echo S2: second UPDATE issued (account 1)
COMMIT;
\echo S2: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
