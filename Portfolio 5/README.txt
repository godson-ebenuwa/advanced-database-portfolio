# Portfolio 5: Distributed and Cloud Database Exercise

**Case study:** Lagos Trust Bank (see Portfolio 1)
**Focus:** replication, high availability, consistency (CAP), sharding design, and cloud deployment (MongoDB Atlas)

## 1. What this portfolio contains

| Part | Type | Files |
|---|---|---|
| Local 3-node replica set on Windows | **Hands-on** | `start_replicaset.bat`, `init_replicaset.bat`, `start_node.bat`, `01_replica_status.js`, `03_failover_heartbeat.js` |
| Write concern, read preference, staleness | **Hands-on** | `02_write_concern_and_read_pref.js` |
| Cloud deployment on MongoDB Atlas | **Hands-on** | `04_atlas_status.js` + Atlas screenshots |
| Sharding design for `transactions` | **Design analysis** | `sharding-design.md` |
| CAP and consistency policy | **Analysis** | `cap-consistency.md` |

## 2. Architecture

```mermaid
flowchart LR
    App["Bank application / mongosh"] -->|writes: w=majority| P[("PRIMARY localhost:27018")]
    P -->|replicates operations| S1[("SECONDARY localhost:27019")]
    P -->|replicates operations| S2[("SECONDARY localhost:27020")]
    App -.->|optional reads| S1
    S1 <-->|heartbeats| S2
    P <-->|heartbeats| S1
```
If the primary dies, the two secondaries hold an election (they have a majority: 2 of 3) and one becomes the new primary. The driver finds it automatically.

## 3. Setup (Windows, no Docker)

**Install MongoDB Community Server** (the `mongod.exe` server) from mongodb.com/try/download/community using the MSI. mongosh is already installed. Note the install folder (look in `C:\Program Files\MongoDB\Server\`) and, if it is not `8.0`, edit the `BIN` line in `start_replicaset.bat` and `start_node.bat`. The data lives in `C:\mongo-rs` (outside the repo, so it is never committed).

```
start_replicaset.bat        (opens 3 mongod windows; allow private networks in the firewall prompt)
init_replicaset.bat         (ONLY the first time; wait about 10 seconds after the nodes start)
```
Set the connection string once per Command Prompt window (the whole line, with quotes):
```
set "RS_URI=mongodb://localhost:27018,localhost:27019,localhost:27020/?replicaSet=lagosRS&serverSelectionTimeoutMS=3000"
```

## 4. Experiments and what to expect

### 4.1 Cluster health
`mongosh "%RS_URI%" --file 01_replica_status.js`
Expect **1 PRIMARY and 2 SECONDARY**, all with health 1, and the line "a MAJORITY needs 2 of 3". **Screenshot it.**

### 4.2 Write concern and read preference
`mongosh "%RS_URI%" --file 02_write_concern_and_read_pref.js > evidence\02_write_concern.txt`
Expect `w:1` to be the fastest, `w:"majority"` slightly slower, and `w:3` the slowest. A secondary read returns the same count as the primary. Stale reads will probably be 0 on one laptop, and the script explains why that proves nothing about the cloud case.

| Write concern | 100 inserts, total | Avg ms per insert (my run, local 3-node set) |
|---|---|---|
| w:1 (primary only) | 223 ms | **2.23** |
| w:"majority" (2 of 3) | 413 ms | **4.13** |
| w:3 (all nodes) | 434 ms | **4.34** |

**What this shows:** waiting for a majority roughly **doubled** the latency of a write (4.13 vs 2.23 ms, about 1.85x), because the primary must wait for at least one secondary to confirm before acknowledging. `w:3` was only slightly slower than `w:"majority"` (4.34 vs 4.13 ms), because the secondaries replicate in parallel, so the wait is about one replication round trip either way. `w:3` is still the worse choice, since it fails entirely if any one node is down. Reading 300 documents from a secondary gave the same count as the primary, and **0 of 300** probe reads were stale. On one laptop replication takes microseconds, which is why this proves nothing about the cloud case. On Atlas, the same `w:"majority"` writes took about 112 ms, which is dominated by network distance to the cloud region.

### 4.3 Failover test (your main evidence)
1. Open Command Prompt **A** and start: `mongosh "%RS_URI%" --file 03_failover_heartbeat.js`
2. In the first few seconds, read which port is PRIMARY in its output.
3. **Close that node's mongod window** with the X button (an abrupt crash is the harsher, more realistic test).
4. Watch window A. Expect a stretch of `FAILED` lines (the election takes roughly 10 to 15 seconds with default settings), then `>>> primary is now: localhost:2702x` and `OK` lines again.
5. The summary prints how many writes failed and the outage length. **Screenshot the whole run.**
6. Restart the dead node: `start_node.bat 27018` (use its port), wait 15 seconds, run `01_replica_status.js` again. It should rejoin as a **SECONDARY** and catch up.

| Result (yours) | |
|---|---|
| Killed node | |
| New primary | |
| Failed writes during election | |
| Outage length (s) | |
| Writes lost after acknowledged `OK`? | none expected |

### 4.4 Losing the majority (the CAP demonstration)
Close **two** of the three mongod windows, then run `03_failover_heartbeat.js` for 20 seconds. Expect **every write to fail**: the surviving node cannot reach a majority, so it steps down to SECONDARY. This is the cluster choosing consistency over availability. Restart the two nodes with `start_node.bat` and confirm recovery.

### 4.5 Cloud deployment on Atlas
Your free Atlas M0 cluster is already a 3-node replica set managed in the cloud.
`mongosh "%MONGO_URI%" --file 04_atlas_status.js > evidence\04_atlas_status.txt`
**Screenshots to take** (hide or blur anything secret):
- Atlas **Database → Cluster overview** showing 3 nodes, the provider and region, and the tier (M0)
- **Network Access** (IP access list) and **Database Access** (usernames only)
- Output of `04_atlas_status.js` listing the primary and members

**Results from my Atlas run (15 November 2026, `evidence/04_atlas_status.txt`):**

| Item | Result |
|---|---|
| Replica set name | `atlas-77lt72-shard-0` |
| Members | 3 (`...shard-00-00`, `...shard-00-01`, `...shard-00-02`), each on port 27017 |
| Primary during the test | `ac-hghnsyk-shard-00-01.rnv9qly.mongodb.net:27017` |
| Avg latency, 20 inserts with `w:"majority"` | **112.2 ms** each |
| Avg latency, 20 inserts with `w:1` | **109.5 ms** each |

**What this shows:** each write takes about 110 ms because of the network distance from my laptop (in Lagos) to the Atlas servers, not because of the database. The extra cost of `w:"majority"` over `w:1` was only about 2.7 ms, because the three Atlas nodes are in the same cloud region and replicate to each other very quickly. That gap is small enough to be run-to-run noise. The main cost of `w:"majority"` is waiting for the replica round trip, and the distance to the client dominates here. A local replica set (section 4.2) has sub-millisecond latency, which is why cloud latency is a design factor for a bank's choice of region.

Compare the local replica set with Atlas:

| | Local (3 mongod on one laptop) | Atlas M0 |
|---|---|---|
| Nodes live on | One machine (no real fault isolation) | Separate servers in a cloud region |
| Failure tolerance | Process crash only | Node and machine failures |
| Latency (w:majority) | Sub-millisecond | Network-bound (see script output) |
| Failover test | You can trigger it | Not on M0 (available on paid tiers) |
| Operations | You run and patch everything | Managed by Atlas |

The local set shows the mechanics, while Atlas shows what production availability looks like. A real bank would use a paid multi-region tier.

## 5. Sharding and CAP
- `sharding-design.md`: why replication is not sharding, the shard-key choice for `transactions` (**recommended `{accountNumber: 1, createdAt: 1}`**, with the rejected alternatives and the cost to cross-account transfers). This is design only and was not executed.
- `cap-consistency.md`: CAP and PACELC applied to this bank, the consistency settings used (write concern, read preference, read concern), the policy per banking operation, and the link to the failover results.

## 6. Reflection hooks (use in your final documentation)
- Replication gives availability and durability, but not extra capacity for writes. Sharding gives capacity, at the price of complexity and costly cross-shard transfers.
- Strong consistency is chosen where money moves, and relaxed for display and reporting.
- A 3-node set tolerates one failure, and a 4th node adds cost but no extra tolerance.
- A local replica set on one laptop demonstrates behaviour, not real fault isolation.

## 7. Evidence checklist
- [ ] Screenshot of `01_replica_status.js` (1 PRIMARY, 2 SECONDARY)
- [ ] `evidence/02_write_concern.txt` with your timing table filled in
- [ ] Failover run output, including the `>>> primary is now` line, and the status after the node rejoined
- [ ] Majority-loss run showing failed writes
- [ ] Atlas screenshots and `evidence/04_atlas_status.txt`
- [ ] README tables filled with your numbers, and the explanations rewritten in your own words
- [ ] Commits such as "Add replica set scripts", "Add failover test evidence", "Add sharding and CAP analysis"
