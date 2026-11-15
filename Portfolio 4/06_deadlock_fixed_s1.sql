-- Session 1 (FIX): always lock the LOWER account_id first, whatever the direction of the transfer
\set ON_ERROR_STOP off
BEGIN;
SELECT account_id FROM account WHERE account_id IN (1,2) ORDER BY account_id FOR UPDATE;
\echo S1: locked accounts 1 and 2 in id order
SELECT pg_sleep(2);
UPDATE account SET balance = balance - 100 WHERE account_id = 1;
UPDATE account SET balance = balance + 100 WHERE account_id = 2;
COMMIT;
\echo S1: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
