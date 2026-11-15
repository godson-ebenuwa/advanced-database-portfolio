# Portfolio 1: Database Design and Modelling

## 1. Case Study Statement

**Organisation:** Lagos Trust Bank (simulated retail bank, Nigeria)

**Nature of the system:** A core retail banking database supporting customer onboarding, account management, deposits, withdrawals, and inter-account transfers, with a full transaction ledger and audit trail.

**Users of the database:**
- Customers (via mobile/internet banking)
- Tellers and customer-service staff
- Operations/reconciliation officers
- Auditors and compliance officers
- Branch managers (reporting)

**Major data stored:** customers (including BVN), branches, account types, accounts and balances, transfers, ledger transactions, audit logs.

**Key operations supported:**
- Open an account for a customer
- Deposit and withdraw funds
- Transfer funds between accounts (atomic debit and credit)
- Reverse failed or disputed transfers
- Audit account balances and produce statements
- Report on transactions per branch/customer/period

## 2. ER Diagram

```mermaid
erDiagram
    CUSTOMER ||--o{ ACCOUNT : owns
    BRANCH ||--o{ ACCOUNT : hosts
    ACCOUNT_TYPE ||--o{ ACCOUNT : classifies
    ACCOUNT ||--o{ ACCOUNT_TRANSACTION : records
    ACCOUNT ||--o{ TRANSFER : "sends (from)"
    ACCOUNT ||--o{ TRANSFER : "receives (to)"
    TRANSFER ||--o{ ACCOUNT_TRANSACTION : "produces ledger entries"

    CUSTOMER {
        int customer_id PK
        varchar first_name
        varchar last_name
        varchar email UK
        varchar phone UK
        char bvn UK
        date date_of_birth
        varchar address
        timestamp created_at
    }
    BRANCH {
        int branch_id PK
        varchar branch_name UK
        varchar city
    }
    ACCOUNT_TYPE {
        int type_id PK
        varchar type_name UK
        numeric min_balance
        numeric interest_rate
    }
    ACCOUNT {
        int account_id PK
        char account_number UK
        int customer_id FK
        int branch_id FK
        int type_id FK
        numeric balance
        varchar status
        timestamp opened_at
    }
    TRANSFER {
        int transfer_id PK
        varchar reference UK
        int from_account_id FK
        int to_account_id FK
        numeric amount
        varchar status
        timestamp initiated_at
    }
    ACCOUNT_TRANSACTION {
        bigint txn_id PK
        int account_id FK
        int transfer_id FK
        varchar txn_type
        numeric amount
        numeric balance_after
        varchar description
        timestamp created_at
    }
    AUDIT_LOG {
        bigint audit_id PK
        varchar table_name
        bigint record_id
        varchar action
        jsonb old_value
        jsonb new_value
        varchar changed_by
        timestamp changed_at
    }
```

`AUDIT_LOG` is intentionally not linked by foreign keys: it stores `table_name` + `record_id` generically so it can record changes to any table and survive deletions.

## 3. Relational Schema

| Table | Primary key | Foreign keys | Other keys/constraints |
|---|---|---|---|
| branch | branch_id | none | UNIQUE(branch_name) |
| customer | customer_id | none | UNIQUE(email, phone, bvn); CHECK bvn is 11 digits; CHECK age >= 18 |
| account_type | type_id | none | UNIQUE(type_name); CHECK min_balance >= 0 |
| account | account_id | customer_id, branch_id, type_id | UNIQUE(account_number); CHECK balance >= 0; CHECK status IN (...) |
| transfer | transfer_id | from_account_id, to_account_id | UNIQUE(reference); CHECK amount > 0; CHECK from <> to |
| account_transaction | txn_id | account_id, transfer_id (nullable) | CHECK amount > 0; CHECK txn_type IN (...) |
| audit_log | audit_id | none | CHECK action IN (...) |

**Referential actions:** all foreign keys use `ON DELETE RESTRICT` (default behaviour for the transfer and ledger keys). Financial records must never be silently deleted with a customer or account.

## 4. Normalisation Explanation

**1NF:** Every column holds a single atomic value; there are no repeating groups (a customer's several accounts are separate rows in `account`, not columns like `account1`, `account2`). Every table has a primary key.

**2NF:** All tables with single-column primary keys automatically have no partial dependencies. The design avoids composite keys, so every non-key attribute depends on the whole key.

**3NF:** No non-key attribute depends on another non-key attribute (no transitive dependencies). Examples:
- `type_name`, `min_balance` and `interest_rate` depend on the account type, not the account, so they live in `account_type` rather than being repeated in `account`.
- Branch name and city live in `branch`, not in `account`.
- Customer details live in `customer`, not repeated per account.

**Deliberate trade-off:** `account.balance` and `account_transaction.balance_after` are derived values, since a balance could be recomputed by summing the ledger. They are kept on purpose for performance (reading a balance in O(1)) and as an audit checkpoint. Portfolio 3 uses transactions and locking to keep them consistent with the ledger.

## 5. How to Run

```bash
psql -U postgres -c "CREATE DATABASE lagos_trust_bank;"
psql -U postgres -d lagos_trust_bank -f schema.sql
```

## 6. Evidence to add to this folder
- [ ] `er-diagram.png` (export the Mermaid diagram, or draw it in dbdiagram.io / pgAdmin)
- [ ] `screenshots/` of the tables created (`\dt`, `\d account`) and the sanity-check query output
- [ ] Commit messages showing progress (e.g. "Add core tables", "Add constraints and seed data")
