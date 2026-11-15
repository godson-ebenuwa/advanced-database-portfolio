-- Writer session: commits a +5000 deposit to account 1 while the reader is sleeping.
SELECT pg_sleep(1);
UPDATE account SET balance = balance + 5000 WHERE account_id = 1;
\echo WRITER: committed deposit of 5000
