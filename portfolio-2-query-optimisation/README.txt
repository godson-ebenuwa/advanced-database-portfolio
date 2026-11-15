# Portfolio 2: Query Processing and Optimisation

**Case study:** Lagos Trust Bank (see `../portfolio-1-database-design/README.md`)
**DBMS:** PostgreSQL 16

## 1. What was done

| Step | File | Purpose |
|---|---|---|
| 1 | `01_seed_data.sql` | Generates 20,003 customers, 30,004 accounts, 50,000 transfers, 300,000 ledger rows so that performance differences are measurable |
| 2 | `02_queries.sql` | Six realistic banking queries run with `EXPLAIN (ANALYZE, BUFFERS)` |
| 3 | (baseline run) | Output saved to `evidence/results_before.txt` |
| 4 | `03_indexes.sql` | Seven indexes chosen from the baseline plans |
| 5 | (re-run) | Output saved to `evidence/results_after.txt` |

**To reproduce:**
```bash
psql -d lagos_trust_bank -f ../portfolio-1-database-design/schema.sql   # fresh database
psql -d lagos_trust_bank -f 01_seed_data.sql
psql -d lagos_trust_bank -f 02_queries.sql > evidence/results_before.txt
psql -d lagos_trust_bank -f 03_indexes.sql
psql -d lagos_trust_bank -f 02_queries.sql > evidence/results_after.txt
```

## 2. The queries

| # | Business purpose | Key SQL features |
|---|---|---|
| Q1 | Account statement: last 90 days for one account | Filter + range + `ORDER BY` |
| Q2 | Teller search by surname and first name | Multi-column equality filter |
| Q3 | All accounts of one customer with branch and type | 3-table join on FK columns |
| Q4 | Failed transfers in the last 90 days (compliance) | Join + filter on status and date |
| Q5 | Top 10 customers by total active balance | Join + `GROUP BY` + `ORDER BY ... LIMIT` |
| Q6 | Monthly transaction volume per type | Full-table analytical aggregate |

## 3. Results

Execution times (ms) from `EXPLAIN ANALYZE` on my machine. **Replace these with the numbers from your own run**, since they vary by hardware and random data.

| Query | Before (ms) | Plan before | After (ms) | Plan after | Change |
|---|---|---|---|---|---|
| Q1 | 28.7 | Parallel Seq Scan (300,000 rows read) | 0.08 | Bitmap Index Scan on `idx_txn_account_created` | about 350x faster |
| Q2 | 1.6 | Seq Scan | 0.34 | Bitmap Index Scan on `idx_customer_name` | about 5x faster |
| Q3 | 1.7 | Seq Scan on account | 0.08 | Index Scan on `idx_account_customer` | about 20x faster |
| Q4 | 13.8 | Seq Scan on transfer | 7.4 | Bitmap Index Scan on partial index | about 2x faster |
| Q5 | 32.7 | Seq Scans + HashAggregate | 27.1 | unchanged | within noise |
| Q6 | 183.9 | Seq Scan + external-merge sort (spills to disk) | 227.3 | unchanged | no benefit (noise) |

Index sizes: `idx_txn_account_created` 9.2 MB, `idx_transfer_from` and `idx_transfer_to` about 0.9 MB each, the rest under 1 MB.

## 4. Performance analysis

**Q1 (biggest win).** Without an index, PostgreSQL scanned all 300,000 ledger rows across 3 parallel workers to find 11 matches. The composite index `(account_id, created_at DESC)` lets it jump directly to one account's entries. Column order matters: the equality column (`account_id`) comes first and the range/sort column (`created_at`) second. The `DESC` ordering also removes the separate sort step. This is the most important index in a bank, because every statement and mobile-app transaction history uses this pattern.

**Q2 and Q3.** Q2 is a straightforward composite-index lookup. Q3 shows a PostgreSQL-specific point: primary keys get an automatic index but **foreign-key columns do not**, so `account.customer_id` was being scanned sequentially. The FK index fixes this and also speeds up cascading checks when customers are updated or deleted.

**Q4 (partial index).** Only about 10% of transfers are `FAILED`, so `idx_transfer_failed_recent` indexes just those rows, which keeps it small. The gain is modest (about 2x) because the join still reads all of `account` with a hash join, which is the right choice when about 1,200 rows join to a 30,000-row table.

**Q5 (limited benefit).** Aggregating balances across almost all active accounts needs to read most of the table, so the planner correctly keeps sequential scans and a hash aggregate. Indexes would not help much here. A real system would use a materialised view or a summary table for this report.

**Q6 (index deliberately not added).** This query reads every ledger row, so no index helps. The sort spilled about 10 MB to disk ("external merge"), which suggests a possible fix: raising `work_mem` for this session, or pre-aggregating into a monthly summary table. The before/after timing difference (184 vs 227 ms) is run-to-run noise, not an effect of the new indexes. It shows why you should repeat measurements.

## 5. Trade-offs

- Indexes slow `INSERT`/`UPDATE`/`DELETE`, because each index must be maintained on every write. This matters most on `account_transaction`, the highest-write table. In a bank, though, reads of statements vastly outnumber the cost of one extra index write, so the trade is justified.
- `idx_txn_account_created` costs 9.2 MB (about 30 bytes per row). Index storage is the price of the faster reads.
- Indexes were created only after measuring, and each one is tied to a query in this README. Q6 deliberately has none.

