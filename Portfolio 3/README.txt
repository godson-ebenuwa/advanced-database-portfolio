# Portfolio 3: Transactions and Concurrency

**Case study:** Lagos Trust Bank (see Portfolio 1)
**DBMS:** PostgreSQL 16 (default isolation level: READ COMMITTED)
**Demo accounts:** account 1 (A, starts at 250,000.00) and account 2 (B, starts at 800,000.00)

## 1. Files

| File | Purpose |
|---|---|
| `00_functions.sql` | `transfer_funds()`, `reverse_transfer()` and `reset_demo()` |
| `01_commit_rollback.sql` | Atomicity demos (commit, rollback, failure half-way, savepoint, reversal) |
| `02_lost_update_s1/s2.sql` | **Problem:** lost update between two sessions |
| `03_fix_for_update_s1/s2.sql` | **Fix 1:** pessimistic locking with `SELECT ... FOR UPDATE` |
| `04_fix_repeatable_read_s1/s2.sql` | **Fix 2:** `REPEATABLE READ` aborts the loser |
| `05_deadlock_s1/s2.sql` | **Problem:** deadlock from opposite lock ordering |
| `06_deadlock_fixed_s1/s2.sql` | **Fix:** lock in a consistent order |
| `07_*.sql` | Dirty read attempt and non-repeatable read across isolation levels |
| `run_all.sh` | Runs everything with two concurrent psql sessions and writes `evidence/` |
| `evidence/` | Captured output of every run |

**To reproduce:** `./run_all.sh lagos_trust_bank`. Without bash (Windows), open two psql windows and start `*_s1.sql` and `*_s2.sql` within about a second of each other. The scripts use `pg_sleep` to force the overlap.

## 2. Atomicity: commit and rollback (`evidence/01_commit_rollback.txt`)

`transfer_funds()` performs five steps: lock both accounts, check the funds, insert the transfer row, debit and credit, and write two ledger rows. It is atomic, so all of it applies or none of it does.

| Demo | What happened |
|---|---|
| 1a COMMIT | A went 250,000 to 200,000 and B 800,000 to 850,000. The change persisted after `COMMIT`. |
| 1b ROLLBACK | A transfer of 20,000 was visible inside the transaction (A = 180,000). After `ROLLBACK`, balances were back to 200,000 / 850,000 and the transfer row did not exist. |
| 1c Failure half-way | A was debited 10,000, then an `INSERT` violated a CHECK constraint. PostgreSQL put the transaction in an aborted state ("current transaction is aborted, commands ignored..."). After `ROLLBACK`, A's balance was unchanged. |
| 1d Insufficient funds | The function raised an exception. No transfer row was created and no balance changed. |
| 1e SAVEPOINT | `ROLLBACK TO SAVEPOINT` undid the second transfer (DEMO-005) while keeping the first (DEMO-004). |
| 1f Reversal | `reverse_transfer('DEMO-001')` moved the money back, wrote two `REVERSAL` ledger rows and set the status to `REVERSED`. |

## 3. Concurrency problem 1: lost update

**Scenario:** two staff members withdraw from the same account at the same time (1,000 and 2,000). Each application reads the balance, computes the new value in code, then writes it back.

| | Balance |
|---|---|
| Start | 250,000 |
| Correct result (both withdrawals applied) | 247,000 |
| **Actual result with no protection** | **248,000** |

Both sessions read 250,000 before either wrote. Session 1 wrote 249,000, then Session 2 wrote 248,000, overwriting Session 1's change. **1,000 was silently lost**, which in a bank means money appearing from nowhere. READ COMMITTED does not prevent this, because each statement is individually consistent. The bug is the read-then-write gap in the application logic. (`evidence/02_lost_update.txt`)

### Fix 1: `SELECT ... FOR UPDATE` (`evidence/03_fix_for_update.txt`)
Session 1 locked the row on read. Session 2's `SELECT ... FOR UPDATE` **waited** until Session 1 committed, then read the new balance of 249,000 and wrote 247,000. **Final balance: 247,000, which is correct.** The cost is that concurrent users of the same account queue up, which is acceptable for money.

### Fix 2: REPEATABLE READ (`evidence/04_fix_repeatable_read.txt`)
With no locks in the code, PostgreSQL detected that Session 2's snapshot was stale and aborted it with `ERROR: could not serialize access due to concurrent update`. **Final balance: 249,000.** Session 1's change is safe and Session 2 did not corrupt it, but **the application must catch the error and retry**. (The "COMMIT issued" line in the log is just psql continuing after the error; the aborted transaction is rolled back.)

### Fix 3: atomic update (no read at all)
`UPDATE account SET balance = balance - 2000 WHERE account_id = 1 AND balance >= 2000;` is also safe, because the read and write happen in one statement under a row lock. `transfer_funds()` combines locking and this style.

## 4. Concurrency problem 2: deadlock

**Scenario:** Session 1 transfers A to B (locks account 1, then 2). Session 2 transfers B to A (locks account 2, then 1). Each holds one lock and waits for the other.

PostgreSQL's deadlock detector stepped in after about a second: `ERROR: deadlock detected ... Process X waits for ShareLock on transaction ...; blocked by process Y`. It aborted one session and let the other finish. In the final run the victim was Session 1, so only Session 2's transfer applied (final: 250,050 / 799,950). **The victim differs from run to run**, since PostgreSQL chooses it. The aborted transfer is not lost silently: the application receives an error and must retry. (`evidence/05_deadlock.txt`)

**Fix: consistent lock ordering** (`evidence/06_deadlock_fixed.txt`). Both sessions locked accounts in `account_id` order with `ORDER BY account_id FOR UPDATE`, even though one was transferring in the opposite direction. The second session simply waited. **Both transfers succeeded, with no error** (final: 249,950 / 800,050). `transfer_funds()` already does this.

## 5. Isolation levels

| Test | Result | Evidence |
|---|---|---|
| **Dirty read** (read uncommitted data). S1 added 999,999 without committing; S2 asked for `READ UNCOMMITTED`. | S2 saw **250,000**, not the uncommitted value. PostgreSQL treats `READ UNCOMMITTED` as `READ COMMITTED`, so dirty reads are **impossible** in PostgreSQL. | `07_dirty_read.txt` |
| **Non-repeatable read** at READ COMMITTED. Reader reads twice while another session commits a +5,000 deposit between the reads. | First read 250,000, second read **255,000** (the value changed inside one transaction). | `07_isolation_READ_COMMITTED.txt` |
| Same test at **REPEATABLE READ** | Both reads returned **250,000**. The transaction works from one snapshot. | `07_isolation_REPEATABLE_READ.txt` |

| Level | Dirty read | Non-repeatable read | Lost update (read-modify-write) |
|---|---|---|---|
| READ COMMITTED (PostgreSQL default) | No | **Possible** | **Possible** (needs locks) |
| REPEATABLE READ | No | No | Prevented (error, then retry) |
| SERIALIZABLE | No | No | Prevented, and phantom/write-skew anomalies as well |

## 6. Design decisions
- **Pessimistic locking (`FOR UPDATE`)** for transfers. Conflicts on a hot account are likely and failing is costly, so waiting beats retrying.
- **Lock order by `account_id`** to avoid deadlocks, plus **retry logic** in the application for the rare serialization failures and deadlocks.
- **One transaction per transfer** covering the transfer row, both balance updates and both ledger rows, so the ledger and `account.balance` (the derived column from Portfolio 1) cannot drift apart.
- **CHECK constraints as a last line of defence**: even buggy application code cannot create a negative balance (`CHECK (balance >= 0)`).

