-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Case study: Lagos Trust Bank (simulated retail bank), PostgreSQL 15+
-- =====================================================================

DROP TABLE IF EXISTS audit_log          CASCADE;
DROP TABLE IF EXISTS account_transaction CASCADE;
DROP TABLE IF EXISTS transfer           CASCADE;
DROP TABLE IF EXISTS account            CASCADE;
DROP TABLE IF EXISTS account_type       CASCADE;
DROP TABLE IF EXISTS customer           CASCADE;
DROP TABLE IF EXISTS branch             CASCADE;

CREATE TABLE branch (
    branch_id    SERIAL PRIMARY KEY,
    branch_name  VARCHAR(80) NOT NULL UNIQUE,
    city         VARCHAR(60) NOT NULL
);

CREATE TABLE customer (
    customer_id  SERIAL PRIMARY KEY,
    first_name   VARCHAR(50) NOT NULL,
    last_name    VARCHAR(50) NOT NULL,
    email        VARCHAR(120) NOT NULL UNIQUE,
    phone        VARCHAR(20)  NOT NULL UNIQUE,
    bvn          CHAR(11)     NOT NULL UNIQUE CHECK (bvn ~ '^[0-9]{11}$'),
    date_of_birth DATE        NOT NULL CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years'),
    address      VARCHAR(200),
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE account_type (
    type_id       SERIAL PRIMARY KEY,
    type_name     VARCHAR(30) NOT NULL UNIQUE,      -- Savings, Current, Fixed
    min_balance   NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (min_balance >= 0),
    interest_rate NUMERIC(5,2)  NOT NULL DEFAULT 0 CHECK (interest_rate >= 0)
);

CREATE TABLE account (
    account_id     SERIAL PRIMARY KEY,
    account_number CHAR(10) NOT NULL UNIQUE CHECK (account_number ~ '^[0-9]{10}$'),
    customer_id    INT NOT NULL REFERENCES customer(customer_id) ON DELETE RESTRICT,
    branch_id      INT NOT NULL REFERENCES branch(branch_id)     ON DELETE RESTRICT,
    type_id        INT NOT NULL REFERENCES account_type(type_id) ON DELETE RESTRICT,
    balance        NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    status         VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE','DORMANT','FROZEN','CLOSED')),
    opened_at      TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE TABLE transfer (
    transfer_id     SERIAL PRIMARY KEY,
    reference       VARCHAR(30) NOT NULL UNIQUE,
    from_account_id INT NOT NULL REFERENCES account(account_id),
    to_account_id   INT NOT NULL REFERENCES account(account_id),
    amount          NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    status          VARCHAR(10) NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','SUCCESS','FAILED','REVERSED')),
    initiated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_diff_accounts CHECK (from_account_id <> to_account_id)
);

CREATE TABLE account_transaction (
    txn_id        BIGSERIAL PRIMARY KEY,
    account_id    INT NOT NULL REFERENCES account(account_id),
    transfer_id   INT REFERENCES transfer(transfer_id),   -- NULL for cash deposits/withdrawals
    txn_type      VARCHAR(15) NOT NULL
                  CHECK (txn_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER_DEBIT','TRANSFER_CREDIT','REVERSAL')),
    amount        NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    balance_after NUMERIC(15,2) NOT NULL CHECK (balance_after >= 0),
    description   VARCHAR(200),
    created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_log (
    audit_id    BIGSERIAL PRIMARY KEY,
    table_name  VARCHAR(40) NOT NULL,
    record_id   BIGINT      NOT NULL,
    action      VARCHAR(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_value   JSONB,
    new_value   JSONB,
    changed_by  VARCHAR(60) NOT NULL DEFAULT CURRENT_USER,
    changed_at  TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- Sample data
-- ---------------------------------------------------------------------
INSERT INTO branch (branch_name, city) VALUES
 ('Ikeja Main', 'Lagos'), ('Victoria Island', 'Lagos'), ('Wuse II', 'Abuja');

INSERT INTO account_type (type_name, min_balance, interest_rate) VALUES
 ('Savings', 0, 4.00), ('Current', 5000, 0.00), ('Fixed Deposit', 100000, 9.50);

INSERT INTO customer (first_name, last_name, email, phone, bvn, date_of_birth, address) VALUES
 ('Adaeze', 'Okafor',  'adaeze@example.com', '08011111111', '22211111111', '1994-03-12', 'Ojota, Lagos'),
 ('Tunde',  'Bello',   'tunde@example.com',  '08022222222', '22222222222', '1989-07-25', 'Ikeja, Lagos'),
 ('Amina',  'Yusuf',   'amina@example.com',  '08033333333', '22233333333', '1991-11-02', 'Wuse, Abuja');

INSERT INTO account (account_number, customer_id, branch_id, type_id, balance) VALUES
 ('0123456789', 1, 1, 1, 250000.00),
 ('0234567891', 2, 2, 2, 800000.00),
 ('0345678912', 3, 3, 1,  50000.00),
 ('0456789123', 1, 1, 3, 500000.00);

-- ---------------------------------------------------------------------
-- Sanity check
-- ---------------------------------------------------------------------
SELECT c.first_name, c.last_name, a.account_number, t.type_name, a.balance
FROM account a
JOIN customer c     ON c.customer_id = a.customer_id
JOIN account_type t ON t.type_id = a.type_id
ORDER BY c.last_name;
