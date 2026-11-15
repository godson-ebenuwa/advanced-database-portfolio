-- =====================================================================
-- Demo 1: atomicity - COMMIT, ROLLBACK, SAVEPOINT, failed transfer
-- Run: psql -d lagos_trust_bank -f 01_commit_rollback.sql
-- =====================================================================
\set ON_ERROR_STOP off
SELECT reset_demo();
\echo '--- Starting balances (A = account 1, B = account 2)'
SELECT account_id, account_number, balance FROM account WHERE account_id IN (1,2) ORDER BY 1;

\echo '=== 1a. COMMIT: successful transfer of 50,000 from A to B ==='
BEGIN;
SELECT transfer_funds('0123456789', '0234567891', 50000, 'DEMO-001');
SELECT account_id, balance FROM account WHERE account_id IN (1,2) ORDER BY 1;
COMMIT;
\echo '--- After COMMIT (change is permanent)'
SELECT account_id, balance FROM account WHERE account_id IN (1,2) ORDER BY 1;

\echo '=== 1b. ROLLBACK: transfer is made, then cancelled ==='
BEGIN;
SELECT transfer_funds('0123456789', '0234567891', 20000, 'DEMO-002');
\echo '--- Inside the transaction (change visible only to this session)'
SELECT account_id, balance FROM account WHERE account_id IN (1,2) ORDER BY 1;
ROLLBACK;
\echo '--- After ROLLBACK (back to previous balances, transfer row also gone)'
SELECT account_id, balance FROM account WHERE account_id IN (1,2) ORDER BY 1;
SELECT count(*) AS demo_002_rows FROM transfer WHERE reference = 'DEMO-002';

\echo '=== 1c. Failure half-way: debit succeeds, next statement fails, everything is undone ==='
BEGIN;
UPDATE account SET balance = balance - 10000 WHERE account_id = 1;
-- This INSERT violates the txn_type CHECK constraint and aborts the transaction:
INSERT INTO account_transaction (account_id, txn_type, amount, balance_after)
VALUES (2, 'BOGUS', 10000, 0);
-- The transaction is now in an aborted state; further statements are refused:
SELECT balance FROM account WHERE account_id = 1;
ROLLBACK;
\echo '--- Account A was debited then rolled back: balance unchanged'
SELECT account_id, balance FROM account WHERE account_id = 1;

\echo '=== 1d. Business-rule failure: insufficient funds (function raises, nothing applied) ==='
SELECT transfer_funds('0345678912', '0123456789', 999999999, 'DEMO-003');
SELECT count(*) AS demo_003_rows FROM transfer WHERE reference = 'DEMO-003';

\echo '=== 1e. SAVEPOINT: undo part of a transaction, keep the rest ==='
BEGIN;
SELECT transfer_funds('0123456789', '0234567891', 1000, 'DEMO-004');
SAVEPOINT after_first;
SELECT transfer_funds('0123456789', '0234567891', 2000, 'DEMO-005');
ROLLBACK TO SAVEPOINT after_first;
COMMIT;
SELECT reference, amount, status FROM transfer WHERE reference IN ('DEMO-004','DEMO-005') ORDER BY 1;

\echo '=== 1f. Reversal of a successful transfer ==='
SELECT reverse_transfer('DEMO-001');
SELECT reference, amount, status FROM transfer WHERE reference IN ('DEMO-001','DEMO-004') ORDER BY 1;
SELECT account_id, balance FROM account WHERE account_id IN (1,2) ORDER BY 1;
SELECT account_id, txn_type, amount, balance_after, description
FROM account_transaction WHERE description LIKE '%DEMO-001' ORDER BY txn_id;
