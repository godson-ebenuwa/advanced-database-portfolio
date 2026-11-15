-- Reader session: reads account 1 balance twice, 3 seconds apart, inside ONE transaction.
-- Run with:  -v level="READ COMMITTED"   or   -v level="REPEATABLE READ"
\set ON_ERROR_STOP off
BEGIN ISOLATION LEVEL :level;
SELECT balance AS first_read FROM account WHERE account_id = 1;
SELECT pg_sleep(3);
SELECT balance AS second_read FROM account WHERE account_id = 1;
COMMIT;
