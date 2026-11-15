-- Session 1: transfer 100 from account 1 -> 2. Locks account 1 FIRST, then account 2.
\set ON_ERROR_STOP off
BEGIN;
UPDATE account SET balance = balance - 100 WHERE account_id = 1;
\echo S1: locked account 1
SELECT pg_sleep(2);
UPDATE account SET balance = balance + 100 WHERE account_id = 2;
\echo S1: second UPDATE issued (account 2)
COMMIT;
\echo S1: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
