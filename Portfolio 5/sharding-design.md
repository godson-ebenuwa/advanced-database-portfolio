# Sharding Design for Lagos Trust Bank (design analysis)

> **Status: design only.** A sharded cluster needs config servers, `mongos` routers and several shards (Atlas M30 or larger, or about 7+ local processes). The free M0 tier cannot shard. The commands below are the reference configuration, not executed here.

## 1. Replication vs sharding
| | Replication | Sharding |
|---|---|---|
| Copies of data | Every node holds **all** data | Each shard holds **a slice** of the data |
| Solves | Availability, durability, read scaling | Storage and write throughput beyond one machine |
| Where in this portfolio | Implemented (3-node replica set, Atlas) | Designed below |

In production, each shard is itself a replica set.

## 2. What to shard
`transactions` is the collection that grows without bound: about 50,000 rows in my test data, but millions per day in a real bank. `customers` (2,000) and `accounts` (3,004) are small and stay unsharded.

## 3. Choosing the shard key
The shard key decides which shard stores each document. The main queries from Portfolio 4:
- Statement: `{accountNumber: X, createdAt: {$gte: ...}}` sorted by date (the most common)
- Reports across all accounts by month or channel (occasional, heavy)
- Writes: a constant stream of inserts, all with "now" as the date

| Candidate key | Statement query | Insert distribution | Verdict |
|---|---|---|---|
| `{createdAt: 1}` | Hits every shard (scatter-gather) | **All new writes land on ONE shard** (a "hot shard", because time increases monotonically) | Rejected |
| `{accountNumber: 1}` (ranged) | Targets one shard | Reasonable, but busy or sequential account numbers can cluster | Acceptable |
| `{accountNumber: "hashed"}` | Targets one shard (all of an account's rows hash to the same shard), but a very busy single account can never be split across shards | Evenly spread, even if account numbers are sequential | Good, with that limit |
| **`{accountNumber: 1, createdAt: 1}`** | Targets **one shard** and the index serves the date range and sort | Spread across accounts; a single very busy account can be split further by `createdAt` | **Recommended** |

**Recommendation:** `{accountNumber: 1, createdAt: 1}`.
- **High cardinality:** millions of accounts, so data can be split into many chunks.
- **Query isolation:** the statement query includes the shard-key prefix, so `mongos` routes it to a single shard instead of asking all of them.
- **Write distribution:** inserts are spread across accounts, so no single hot shard.
- **Chunk splitting:** the `createdAt` suffix lets MongoDB split a very active account's data into several chunks, avoiding "jumbo chunks".

**Cost:** the monthly report across all accounts must query every shard, with results merged by `mongos`. That is acceptable for an occasional report, and a pre-aggregated summary collection can serve it.

## 4. Reference commands (not executed)
```javascript
sh.enableSharding("lagos_trust_bank_nosql")
db.transactions.createIndex({ accountNumber: 1, createdAt: 1 })
sh.shardCollection("lagos_trust_bank_nosql.transactions", { accountNumber: 1, createdAt: 1 })
sh.status()   // shows chunk distribution across shards
db.transactions.find({ accountNumber: "0123456789", createdAt: { $gte: ISODate("2026-08-01") } }).explain()
//  -> winningPlan.stage "SINGLE_SHARD" confirms the query was targeted at one shard
```

## 5. Zones and data residency
Zone sharding can pin ranges of data to shards in specific locations, for example keeping all Nigerian customers' data on shards hosted in-country. Check the bank's actual data protection obligations before relying on this, but the mechanism exists.

## 6. Sharding vs the other portfolios
- **Transfers (P3, P4):** a transfer touches two accounts that may live on different shards, so it becomes a **distributed transaction**, which is slower and more complex. This is a real cost of sharding the core ledger, and one reason the ledger stays relational and un-sharded until scale demands it.
- **Unique indexes** must include the shard key, so `transferRef` uniqueness would need extra design.
- **Alternatives to sharding first:** better indexes (P2), archiving old transactions, read replicas, and a larger machine are all cheaper than sharding and should be tried first.
