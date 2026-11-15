-- Session 2 asks for READ UNCOMMITTED, the lowest level (the one that allows dirty reads in the SQL standard).
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
SELECT pg_sleep(1);
SELECT balance AS balance_seen_by_s2 FROM account WHERE account_id = 1;
COMMIT;
