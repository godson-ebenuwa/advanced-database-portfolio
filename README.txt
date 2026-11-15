# Advanced Database Systems Portfolio (MIT 8103)

**Student:** Godson Ebenuwa
**Student ID:** 301928115
**Course:** MIT 8103 Advanced Database Systems
**Repository:** private GitHub repository

## 1. Selected case study

**Organisation:** Lagos Trust Bank, a simulated retail bank in Nigeria.

**Nature of the system:** a core retail banking database supporting customer onboarding, account management, deposits, withdrawals and inter-account transfers, with a transaction ledger and an audit trail.

**Users of the database:** customers (mobile and internet banking), tellers and customer-service staff, operations and reconciliation officers, auditors and compliance officers, branch managers.

**Major data stored:** customers (including BVN), branches, account types, accounts and balances, transfers, ledger transactions, audit logs, plus (in the NoSQL part) device and KYC profile data, channel-specific transaction details, sessions and one-time passwords.

**Key operations supported:** open an account, deposit and withdraw, transfer funds atomically, reverse failed transfers, audit balances and produce statements, and report on transactions by branch, customer, channel and period.

The same case study is used consistently across all five portfolios.

## 2. Portfolio overview

| # | Portfolio | Folder | Technology | What it shows |
|---|---|---|---|---|
| 1 | Database design and modelling | [`portfolio-1-database-design`](portfolio-1-database-design) | PostgreSQL | ER diagram, relational schema, keys, constraints, normalisation to 3NF |
| 2 | Query processing and optimisation | [`portfolio-2-query-optimisation`](portfolio-2-query-optimisation) | PostgreSQL | 6 queries on about 400,000 rows, `EXPLAIN ANALYZE` before and after indexing, performance analysis |
| 3 | Transactions and concurrency | [`portfolio-3-transactions-concurrency`](portfolio-3-transactions-concurrency) | PostgreSQL | Commit and rollback, lost update, `FOR UPDATE`, deadlock and its fix, isolation levels |
| 4 | NoSQL and advanced data models | [`portfolio-4-nosql`](portfolio-4-nosql) | MongoDB Atlas, Redis | Document model, aggregation, indexing, transfers without SQL transactions, key-value use cases |
| 5 | Distributed and cloud database | [`portfolio-5-distributed-cloud`](portfolio-5-distributed-cloud) | MongoDB replica set, Atlas | Replication, failover, write concern, CAP and consistency, sharding design |

Each folder has its own `README.md` explaining what was done, how to run it and how it was tested, plus an `evidence` or `screenshots` folder with outputs.


## 3. Tools and environment

| Tool | Used for | Version |
|---|---|---|
| PostgreSQL and pgAdmin 4 | Portfolios 1 to 3 | [FILL IN: for example 16.x] |
| psql (Command Prompt) | Running the two-session concurrency demos | [FILL IN] |
| MongoDB Atlas (free M0 tier) | Portfolio 4 and the cloud part of Portfolio 5 | managed |
| mongosh | Running all MongoDB scripts | [FILL IN] |
| MongoDB Community Server | Local 3-node replica set (Portfolio 5) | 9.0.8 |
| Redis | Key-value use cases (Portfolio 4) | [FILL IN: Redis Cloud or Memurai, version] |
| Git and GitHub | Version control and submission | [FILL IN] |
| Operating system | Windows 11, no virtualisation available (so no Docker) | |

## 4. Repository structure

```
advanced-database-portfolio/
├── README.md                              (this file)
├── portfolio-1-database-design/           schema.sql, ER diagram, README, screenshots
├── portfolio-2-query-optimisation/        seed, queries, indexes, before/after plans, README
├── portfolio-3-transactions-concurrency/  functions, demo sessions (_s1/_s2), evidence, README
├── portfolio-4-nosql/                     MongoDB scripts, Redis commands, evidence, README
└── portfolio-5-distributed-cloud/         replica set scripts, Atlas evidence, design documents, README
```

## 5. How to reproduce the work

Run in this order (details are in each portfolio README):

1. **Portfolio 1:** create the database `lagos_trust_bank`, then run `schema.sql` in pgAdmin.
2. **Portfolio 2:** run `01_seed_data.sql` once, run `02_queries.sql` with `psql` (it uses psql commands), run `03_indexes.sql`, then run the queries again to compare.
3. **Portfolio 3:** run `00_functions.sql`, then `01_commit_rollback.sql`. For each demo, open two Command Prompt windows and run the `_s1.sql` and `_s2.sql` files within about a second of each other. Run `SELECT reset_demo();` before each demo.
4. **Portfolio 4:** create a free Atlas cluster, set your connection string in an environment variable (never in a file), then run the `.js` scripts with `mongosh`. Run the Redis commands from `06_redis_commands.md`.
5. **Portfolio 5:** run `04_atlas_status.js` against Atlas. For the local replica set, install MongoDB Community Server, run `start_replicaset.bat`, then `init_replicaset.bat` once, then the scripts.

**Secrets:** no passwords or connection strings are stored in this repository. They are set as environment variables in the terminal for each session.

## 6. Academic integrity and AI use

I used an AI assistant (Chatgpt) as a learning aid. The full **AI Use Declaration** is in my LMS submission document and states the tool used, what it was used for, and how I reviewed, ran, corrected and verified the output. I ran every script myself, produced my own screenshots and results, and can explain each design decision and result. 

## 7. References
PostgreSQL manual (postgresql.org/docs), MongoDB manual (mongodb.com/docs), Redis documentation (redis.io/docs)