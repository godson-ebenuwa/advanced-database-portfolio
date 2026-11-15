# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** Lagos Trust Bank (same bank as Portfolios 1-3)
**Models used:** Document store (**MongoDB 7**) as the main model, plus Key-value store (**Redis 7**) for caching, expiry and counters.

## 1. Files

| File | Purpose |
|---|---|
| `helpers.js` | Shared helper functions (formatting, timing, explain summary) |
| `01_schema_and_seed.js` | Collections, JSON-Schema validation, and test data (2,000 customers, 3,004 accounts, 50,120 transactions) |
| `02_queries.js` | CRUD and query examples (Q1-Q7) |
| `03_aggregations.js` | Aggregation pipelines (A1-A5) |
| `04_indexes.js` | Indexes, `explain()` and timing before/after |
| `05_transfer.js` | Money transfer with guards, idempotency, compensation and a multi-document transaction |
| `06_redis_keyvalue.sh` | Redis use cases |
| `evidence/06_redis_output.txt` | Captured Redis output (a blank line after a command means `(nil)`) |

## 2. How to run

```bash
docker run -d --name mongo -p 27017:27017 mongo:7        # or use a free MongoDB Atlas cluster
docker run -d --name redis -p 6379:6379 redis:7
cd portfolio-4-nosql
mongosh --file 01_schema_and_seed.js
mongosh --file 02_queries.js
mongosh --file 03_aggregations.js
mongosh --file 04_indexes.js > evidence/04_indexes_output.txt
mongosh --file 05_transfer.js
bash 06_redis_keyvalue.sh
```
Run the scripts from inside this folder (they `load('helpers.js')`). For Atlas, replace `mongosh` with `mongosh "<connection-string>"`.

## 3. Why NoSQL for parts of a bank

A bank's core ledger fits a relational database well (Portfolios 1-3). Some parts of the system fit a document or key-value store better:

| Need | Relational pain | NoSQL fit |
|---|---|---|
| **Customer profile**: addresses, KYC documents, registered devices, preferences. These vary in size per customer and are always read together. | Many tables and joins for one screen | **One document** holds it all, with one read and no joins |
| **Transactions from different channels** (mobile, USSD, ATM, POS, web). Each channel records different details. | Many NULL columns, or one extra table per channel | **Polymorphic documents**: every transaction has the common fields, and `meta` holds channel-specific ones |
| **Sessions, OTPs, rate limits, caches** | Needs cleanup jobs and extra load on the main DB | **Redis** keys expire automatically and are served from memory |
| Horizontal scale of a huge, append-only transaction history | Hard to shard a relational ledger | MongoDB sharding (see Portfolio 5) |

**What I kept relational and why:** the authoritative double-entry ledger and cross-account integrity checks (Portfolio 3) benefit most from SQL constraints and multi-row ACID transactions. In a real bank, MongoDB and Redis would sit beside PostgreSQL, not replace it.

## 4. Document model

```
customers                         accounts                        transactions
---------                         --------                        ------------
_id                               _id                             _id
customerNo (unique)               accountNumber (unique)          accountNumber  --> accounts
name {first, last}                customerId  --> customers       type, amountKobo, balanceAfterKobo
email (unique), bvn (unique)      branch {branchId, name, city}   channel: MOBILE|USSD|ATM|POS|WEB
addresses [ {...} ]   EMBEDDED    type, status                    meta { channel-specific fields }
kyc { tier, documents[] } EMBEDDED  balanceKobo (long)            createdAt, yearMonth
devices [ {...} ]     EMBEDDED    openedAt
preferences {...}     EMBEDDED                                    transfers
                                                                  ---------
                                                                  reference (unique), fromAccount, toAccount,
                                                                  amountKobo, status, createdAt
```

### Embed or reference? The decisions
| Data | Choice | Reason |
|---|---|---|
| Addresses, KYC documents, devices, preferences inside `customers` | **Embed** | Small, bounded, owned by one customer, always read together |
| Accounts | **Reference** (`customerId`) | Accounts are updated constantly (balance) and by other processes; embedding would make every balance change rewrite the whole customer document |
| Transactions | **Reference** (`accountNumber`) | Unbounded growth (embedding would hit the 16 MB document limit) and written very frequently |
| Branch name and city inside `accounts` | **Embed a copy** (duplicated) | Rarely changes, avoids a join on every account read. The trade-off is that a branch rename must update all its accounts. |
| `yearMonth` on transactions | **Computed pattern** | Precomputed so monthly reports are a plain `$group` with no date arithmetic |

### Money representation
Amounts are stored as **64-bit integers in kobo** (`NumberLong`). Binary floating point (`0.1 + 0.2 != 0.3`) is unsafe for money. `Decimal128` is the other correct choice. The validator enforces `balanceKobo >= 0`, the equivalent of `CHECK (balance >= 0)` in Portfolio 1.

### Schema flexibility with guardrails
MongoDB is schema-flexible but not schema-less. `01_schema_and_seed.js` attaches a `$jsonSchema` **validator** to each collection (required fields, enums for `type`, `status` and `channel`, a regex for the 10-digit account number and the 11-digit BVN). Flexible parts (`meta`) are left open on purpose.

**Validator test result (my run on Atlas):** inserting an account with `balanceKobo: NumberLong('-5')` was rejected with `MongoServerError: Document failed validation`. The `minimum: 0` rule in the `$jsonSchema` validator did the job of `CHECK (balance >= 0)` from Portfolio 1.

## 5. Queries (`02_queries.js`)
| # | Operation | Demonstrates |
|---|---|---|
| Q1 | Find customer by email with a projection | One read replaces a multi-table join |
| Q2 | Accounts of a customer | Reference lookup |
| Q3 | Statement, last 90 days, newest first | Filter + sort + limit (126 matching rows for the demo account) |
| Q4 | USSD transactions over NGN 100,000 | Query on a channel-specific field in `meta` |
| Q5 | Customers with an Android device | Query inside an embedded array |
| Q6 | `$push` a device and `$set` nested fields | In-place update of embedded data |
| Q7 | Upsert and delete | `$setOnInsert`, `deleteOne` |

## 6. Aggregations (`03_aggregations.js`)
| # | Pipeline | Stages |
|---|---|---|
| A1 | Volume and value by channel | `$group`, `$sort` |
| A2 | Monthly deposits vs withdrawals, last 6 months | `$match`, `$group`, `$sort` |
| A3 | Top 5 accounts by withdrawals | `$match`, `$group`, `$sort`, `$limit` |
| A4 | Device OS distribution | `$unwind`, `$group` |
| A5 | Top 5 customers by balance, with names | `$group`, `$lookup` (the NoSQL join), `$unwind`, `$project` |

> The seed data is random and for performance testing only, so the numbers will not reconcile with real ledger balances.

## 7. Indexing (`04_indexes.js`)

| Index | Why |
|---|---|
| `transactions {accountNumber:1, createdAt:-1}` | Statement query: equality field first, sort field second (same principle as Portfolio 2) |
| `customers {email:1}` unique, `{bvn:1}` unique | Fast lookup and uniqueness (like a UNIQUE constraint) |
| `accounts {accountNumber:1}` unique, `{customerId:1}` | Natural key and reference lookup |
| `transactions {amountKobo:-1}` **partial** (>= NGN 1,000,000) | Anti-money-laundering monitoring: tiny index covering only large transactions |
| `otp_codes {createdAt:1}` **TTL**, 300 s | Documents delete themselves after 5 minutes |

**What to record from your run** (paste your own numbers; `explain("executionStats")` gives them):

| Query | Before | After |
|---|---|---|
| Statement (Q3) | stage `COLLSCAN`, docsExamined = 50,120 (whole collection) | stage `IXSCAN`, docsExamined about 126, no separate SORT stage |
| Customer by email | `COLLSCAN`, 2,000 docs | `IXSCAN`, 1 doc |
| Accounts of customer | `COLLSCAN`, 3,004 docs | `IXSCAN`, 1 to 2 docs |
| Average time (ms) | *your number* | *your number* |

## 8. Transfers (`05_transfer.js`): the key difference from PostgreSQL

MongoDB makes **one document** atomic, but a transfer changes **two accounts**. Portfolio 3 used a single SQL transaction. Here the script uses:

1. **Intent record with a unique `reference`**. A client retry hits the unique index and is ignored, so there is no double payment. (Demo 5c)
2. **Guarded atomic debit**: `findOneAndUpdate({balanceKobo: {$gte: amt}, status: 'ACTIVE'}, {$inc: ...})`. The check and the change happen atomically on one document, so two concurrent withdrawals cannot both succeed. (Demo 5e: NGN 1,000 balance, two NGN 800 withdrawals, the second fails.)
3. **Credit, with compensation**: if the destination is invalid, the debit is refunded. This is the *saga* pattern. (Demo 5d)
4. **Ledger entries** for both sides, and a final status. A ledger check confirms total debits equal total credits.
5. **Multi-document ACID transaction** (demo 5f): `startTransaction` / `commitTransaction` makes both updates atomic, like SQL. It needs a **replica set** (Atlas has one by default). On a standalone server it is skipped, which is a good reason to set up the replica set in Portfolio 5.

**Trade-off:** the saga approach works without a transaction but is more code and briefly shows intermediate states (debited, not yet credited). SQL gives that atomicity for free, which is why the core ledger stays relational.

## 9. Redis key-value use cases (`06_redis_keyvalue.sh`, output in `evidence/`)

| # | Use case | Commands | Result |
|---|---|---|---|
| 1 | Balance cache | `SET ... EX 60`, `DECRBY` | TTL 60 s; atomic integer update |
| 2 | Idempotency key | `SET key v NX EX 86400` | First `OK`, retry `(nil)` |
| 3 | Brute-force limit | `INCR`, `EXPIRE` | Attempt 6 within 15 minutes is blocked |
| 4 | OTP with expiry | `SET ... EX 2` | Value present, then `(nil)` after 3 seconds |
| 5 | Short lock | `SET ... NX PX 5000` | Worker B refused while A holds the lock |
| 6 | Session | `HSET`, `EXPIRE`, `HGETALL` | Hash with automatic expiry |
| 7 | Leaderboard | `ZINCRBY`, `ZREVRANGE` | Top spenders in sorted order, updated in real time |

**Limits:** Redis keeps data in memory, so persistence is optional (RDB/AOF) and a cache can be lost. It must never be the system of record for balances. The cached balance in use case 1 is a read-through copy, and the database stays authoritative.

## 10. Relational vs MongoDB: honest comparison

| | PostgreSQL (Portfolios 1-3) | MongoDB (this portfolio) |
|---|---|---|
| Customer 360 view | Several joins | One document read |
| Schema change (new channel field) | `ALTER TABLE` or a new table | Just write the new field |
| Cross-account transfer | One ACID transaction | Saga, or multi-document transaction on a replica set |
| Integrity rules | FK, CHECK, UNIQUE enforced everywhere | Validator + unique indexes, but no foreign keys |
| Ad-hoc reporting and joins | Excellent | Possible (`$lookup`) but heavier |
| Horizontal scaling | Harder | Built-in sharding |

## 11. Compatibility note
Validators, `$lookup`, partial indexes, TTL indexes and multi-document transactions are standard MongoDB features. Some MongoDB-compatible servers (e.g. FerretDB) do not implement them, and the scripts print `SKIPPED` instead of failing. Use real MongoDB or Atlas for your evidence.


