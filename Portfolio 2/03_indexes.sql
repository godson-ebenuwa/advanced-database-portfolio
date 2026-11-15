-- =====================================================================
-- Portfolio 2: indexing strategy
-- PostgreSQL does NOT automatically index foreign-key columns, so FK joins
-- and lookups scan the whole table until we add indexes ourselves.
-- =====================================================================

-- Q1: statement lookup. Equality column first, range/sort column second.
-- DESC matches ORDER BY created_at DESC so no separate sort step is needed.
CREATE INDEX idx_txn_account_created
    ON account_transaction (account_id, created_at DESC);

-- Q2: composite index for teller search by surname + first name.
CREATE INDEX idx_customer_name
    ON customer (last_name, first_name);

-- Q3, Q5: FK columns used in joins and filters.
CREATE INDEX idx_account_customer ON account (customer_id);
CREATE INDEX idx_account_branch   ON account (branch_id);

-- Q4: PARTIAL index. Only ~10% of transfers are FAILED, so indexing just
-- those rows gives a much smaller index than indexing every row.
CREATE INDEX idx_transfer_failed_recent
    ON transfer (initiated_at DESC)
    WHERE status = 'FAILED';

-- Supports joins from transfer to the sending/receiving account.
CREATE INDEX idx_transfer_from ON transfer (from_account_id);
CREATE INDEX idx_transfer_to   ON transfer (to_account_id);

-- Refresh statistics so the planner sees the new indexes with accurate numbers.
ANALYZE;

-- NOTE: no index is created for Q6 (monthly aggregate over the whole ledger).
-- It must read every row, so an index would add write cost without helping.
-- This is a deliberate decision, discussed in the README.
