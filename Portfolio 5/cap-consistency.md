# Consistency, Availability and the CAP Theorem for Lagos Trust Bank

## 1. CAP in one paragraph
When the network between nodes breaks (a **P**artition), a distributed database must choose between **C**onsistency (every read sees the latest write, so refuse some requests) and **A**vailability (every request gets an answer, which may be stale). Without a partition you can have both, but there is still a trade-off between consistency and **latency** (the PACELC view: *else* latency vs consistency).

## 2. Where this bank's databases sit
| System | Behaviour during a partition | Leaning |
|---|---|---|
| **MongoDB replica set** (default settings) | Only the side holding a **majority** of voting nodes can elect a primary and accept writes. The minority side cannot write. | **CP** for writes |
| MongoDB secondary reads (`readPreference: secondary`) | Served even from a cut-off node, possibly stale | **AP** for reads (eventual consistency) |
| **Redis cache** (single node or async replica) | Always answers; data may be stale or lost on failover | AP / best effort |
| **PostgreSQL** with one primary and **synchronous** replication | Primary stops committing if the sync replica is unreachable | CP |
| PostgreSQL with **asynchronous** replication | Primary keeps committing, but a failover can lose the last few transactions | AP-ish (durability risk) |

PostgreSQL replication was not set up in this portfolio. It is described here for comparison.

## 3. The consistency knobs used in this portfolio
| Setting | What it controls | Effect |
|---|---|---|
| **Write concern** `w:1` | Primary alone acknowledges | Fast, but the write can be lost if the primary crashes before replicating (rolled back on failover) |
| `w:"majority"` | A majority of nodes have the write | Survives failover, slightly slower (see `02_write_concern_and_read_pref.js`) |
| `w:3` | All nodes | Slowest, and fails if any node is down. Rarely a good choice. |
| **Read preference** `primary` / `secondary` | Which node answers reads | `secondary` scales reads but may be stale |
| **Read concern** `majority` | Only return data confirmed by a majority | Never returns data that could be rolled back |

## 4. Policy for each banking operation
| Operation | Consistency needed | Setting | Why |
|---|---|---|---|
| Debit/credit a transfer | **Strong** | Primary, `w:"majority"`, guarded atomic update (P4) or SQL transaction (P3) | Losing or duplicating money is unacceptable |
| Check balance before a withdrawal | **Strong** | Primary read | A stale balance enables overdrafts |
| Show balance in the mobile app home screen | Eventual is fine | Redis cache (TTL 60 s) or secondary read | Speed matters more, and the screen can show "as of" time |
| Monthly statement or analytics report | Eventual is fine | Secondary read | Heavy read must not slow the primary |
| Fraud and rate limiting | Fast, approximate | Redis | Millisecond decisions |
| Audit log | Durable | `w:"majority"` | Must survive failures |

**Principle:** use the strongest consistency only where money is at stake, and relax it for display and reporting, where the cost is speed.

## 5. Evidence from the experiments
- **Failover (`03_failover_heartbeat.js`):** when the primary was killed, writes failed for a short election period, then a new primary took over and `w:"majority"` writes resumed with no acknowledged write lost. That is availability returning without sacrificing consistency.
- **Majority loss:** with two of three nodes down, the survivor cannot form a majority, steps down to SECONDARY, and **rejects writes**. It chose consistency over availability, which is CP in action.
- **Write concern timings:** `w:"majority"` costs extra latency versus `w:1`.
- **Link to Portfolio 3:** the lost update was a consistency bug inside one database, fixed with locking. Here consistency across several copies is handled by replication settings.

## 6. Availability numbers
A 3-node replica set tolerates **1** node failure and keeps accepting writes (majority = 2). With 5 nodes it tolerates 2. An even number of voting nodes adds cost without extra tolerance: 4 nodes still need 3 for a majority, so they tolerate only 1 failure, the same as 3 nodes.
