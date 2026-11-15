-- =====================================================================
-- Portfolio 3: transaction logic for Lagos Trust Bank
-- Run after Portfolio 1 (schema) so the demo accounts exist.
-- Demo accounts: account_id 1 (0123456789, Savings) and 2 (0234567891, Current)
-- =====================================================================

-- Atomic funds transfer: either every step succeeds, or none are applied.
CREATE OR REPLACE FUNCTION transfer_funds(
    p_from   CHAR(10),
    p_to     CHAR(10),
    p_amount NUMERIC,
    p_ref    VARCHAR
) RETURNS INT AS $$
DECLARE
    v_from account%ROWTYPE;
    v_to   account%ROWTYPE;
    v_min  NUMERIC;
    v_tid  INT;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;
    IF p_from = p_to THEN
        RAISE EXCEPTION 'Cannot transfer to the same account';
    END IF;

    -- Lock BOTH accounts up front, always in account_id order.
    -- A consistent lock order is what prevents deadlocks (see 04_deadlock_*).
    PERFORM 1 FROM account
     WHERE account_number IN (p_from, p_to)
     ORDER BY account_id
     FOR UPDATE;

    -- Re-read AFTER locking so we see the latest committed balances.
    SELECT * INTO v_from FROM account WHERE account_number = p_from;
    IF NOT FOUND THEN RAISE EXCEPTION 'Source account % not found', p_from; END IF;
    SELECT * INTO v_to FROM account WHERE account_number = p_to;
    IF NOT FOUND THEN RAISE EXCEPTION 'Destination account % not found', p_to; END IF;

    IF v_from.status <> 'ACTIVE' OR v_to.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Both accounts must be ACTIVE';
    END IF;

    SELECT min_balance INTO v_min FROM account_type WHERE type_id = v_from.type_id;
    IF v_from.balance - p_amount < v_min THEN
        RAISE EXCEPTION 'Insufficient funds: balance %, amount %, minimum balance %',
                        v_from.balance, p_amount, v_min;
    END IF;

    INSERT INTO transfer (reference, from_account_id, to_account_id, amount, status)
    VALUES (p_ref, v_from.account_id, v_to.account_id, p_amount, 'PENDING')
    RETURNING transfer_id INTO v_tid;

    UPDATE account SET balance = balance - p_amount WHERE account_id = v_from.account_id;
    UPDATE account SET balance = balance + p_amount WHERE account_id = v_to.account_id;

    INSERT INTO account_transaction (account_id, transfer_id, txn_type, amount, balance_after, description)
    VALUES (v_from.account_id, v_tid, 'TRANSFER_DEBIT',  p_amount, v_from.balance - p_amount, 'Transfer ' || p_ref),
           (v_to.account_id,   v_tid, 'TRANSFER_CREDIT', p_amount, v_to.balance   + p_amount, 'Transfer ' || p_ref);

    UPDATE transfer SET status = 'SUCCESS' WHERE transfer_id = v_tid;
    RETURN v_tid;
END;
$$ LANGUAGE plpgsql;

-- Reverse a successful transfer (failed/disputed transaction handling).
CREATE OR REPLACE FUNCTION reverse_transfer(p_ref VARCHAR) RETURNS VOID AS $$
DECLARE
    t      transfer%ROWTYPE;
    v_from account%ROWTYPE;
    v_to   account%ROWTYPE;
BEGIN
    SELECT * INTO t FROM transfer WHERE reference = p_ref FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer % not found', p_ref; END IF;
    IF t.status <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Only SUCCESS transfers can be reversed (current status: %)', t.status;
    END IF;

    PERFORM 1 FROM account
     WHERE account_id IN (t.from_account_id, t.to_account_id)
     ORDER BY account_id FOR UPDATE;

    SELECT * INTO v_from FROM account WHERE account_id = t.from_account_id;
    SELECT * INTO v_to   FROM account WHERE account_id = t.to_account_id;

    IF v_to.balance < t.amount THEN
        RAISE EXCEPTION 'Cannot reverse: receiving account only has %', v_to.balance;
    END IF;

    UPDATE account SET balance = balance - t.amount WHERE account_id = t.to_account_id;
    UPDATE account SET balance = balance + t.amount WHERE account_id = t.from_account_id;

    INSERT INTO account_transaction (account_id, transfer_id, txn_type, amount, balance_after, description)
    VALUES (t.to_account_id,   t.transfer_id, 'REVERSAL', t.amount, v_to.balance - t.amount,   'Reversal of ' || p_ref),
           (t.from_account_id, t.transfer_id, 'REVERSAL', t.amount, v_from.balance + t.amount, 'Reversal of ' || p_ref);

    UPDATE transfer SET status = 'REVERSED' WHERE transfer_id = t.transfer_id;
END;
$$ LANGUAGE plpgsql;

-- Put demo accounts back to a known state between experiments.
CREATE OR REPLACE FUNCTION reset_demo() RETURNS VOID AS $$
BEGIN
    DELETE FROM account_transaction
     WHERE transfer_id IN (SELECT transfer_id FROM transfer WHERE reference LIKE 'DEMO%');
    DELETE FROM transfer WHERE reference LIKE 'DEMO%';
    UPDATE account SET balance = 250000.00 WHERE account_id = 1;
    UPDATE account SET balance = 800000.00 WHERE account_id = 2;
END;
$$ LANGUAGE plpgsql;
