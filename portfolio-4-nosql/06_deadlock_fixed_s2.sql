-- Session 2 (FIX): transfers 2 -> 1 but STILL locks in id order (1 then 2), so it waits instead of deadlocking
\set ON_ERROR_STOP off
BEGIN;
SELECT pg_sleep(0.5);
SELECT account_id FROM account WHERE account_id IN (1,2) ORDER BY account_id FOR UPDATE;
\echo S2: locked accounts 1 and 2 in id order (after S1 finished)
UPDATE account SET balance = balance - 50 WHERE account_id = 2;
UPDATE account SET balance = balance + 50 WHERE account_id = 1;
COMMIT;
\echo S2: COMMIT issued (acts as ROLLBACK if the transaction was aborted)
