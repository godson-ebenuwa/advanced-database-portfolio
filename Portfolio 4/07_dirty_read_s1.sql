-- Dirty read attempt: Session 1 changes the balance but does NOT commit yet.
BEGIN;
UPDATE account SET balance = balance + 999999 WHERE account_id = 1;
\echo S1: uncommitted +999999 applied
SELECT pg_sleep(3);
ROLLBACK;
\echo S1: rolled back
