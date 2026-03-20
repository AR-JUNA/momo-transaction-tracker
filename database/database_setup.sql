CREATE DATABASE IF NOT EXISTS momo_sms_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE momo_sms_db;

-- ============================================================
-- TABLE 1: transaction_categories
-- Stores the different types of MoMo transactions
-- ============================================================
CREATE TABLE transaction_categories (
    category_id       INT           NOT NULL AUTO_INCREMENT,
    category_name     VARCHAR(50)   NOT NULL COMMENT 'Type of transaction e.g DEPOSIT, WITHDRAWAL',
    description       VARCHAR(255)      NULL COMMENT 'What this transaction type means',
    requires_agent    TINYINT(1)    NOT NULL DEFAULT 0 COMMENT '1 means agent must be involved',
    requires_merchant TINYINT(1)    NOT NULL DEFAULT 0 COMMENT '1 means merchant must be involved',
    created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_categories   PRIMARY KEY (category_id),
    CONSTRAINT uq_cat_name     UNIQUE (category_name),
    CONSTRAINT chk_cat_name    CHECK (CHAR_LENGTH(TRIM(category_name)) > 0)
) ENGINE=InnoDB COMMENT='Lookup table for MoMo transaction types';


-- ============================================================
-- TABLE 2: users
-- Everyone in the system - customers, agents, merchants
-- ============================================================
CREATE TABLE users (
    user_id      INT          NOT NULL AUTO_INCREMENT,
    phone_number VARCHAR(20)  NOT NULL COMMENT 'Phone number in international format',
    full_name    VARCHAR(100)     NULL COMMENT 'Full name parsed from SMS message',
    account_type VARCHAR(20)  NOT NULL DEFAULT 'PERSONAL'
                                       COMMENT 'PERSONAL, MERCHANT, AGENT or UNKNOWN',
    is_active    TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '1=active 0=disabled',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                       ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_users        PRIMARY KEY (user_id),
    CONSTRAINT uq_phone        UNIQUE (phone_number),
    CONSTRAINT chk_phone       CHECK (phone_number REGEXP '^\\+?[0-9]{7,15}$')
) ENGINE=InnoDB COMMENT='All participants in the MoMo system';

CREATE INDEX idx_users_name ON users (full_name);
CREATE INDEX idx_users_type ON users (account_type);


-- ============================================================
-- TABLE 3: wallets
-- Each user has one wallet that tracks their balance
-- ============================================================
CREATE TABLE wallets (
    wallet_id           INT           NOT NULL AUTO_INCREMENT,
    user_id             INT           NOT NULL COMMENT 'Which user owns this wallet',
    current_balance     DECIMAL(15,2) NOT NULL DEFAULT 0.00
                                               COMMENT 'Current wallet balance in RWF',
    daily_limit         DECIMAL(15,2) NOT NULL DEFAULT 10000000.00
                                               COMMENT 'Max amount allowed per day (MTN regulation)',
    wallet_status       VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE'
                                               COMMENT 'ACTIVE, FROZEN or CLOSED',
    last_transaction_at DATETIME          NULL COMMENT 'When was the last transaction done',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_wallets       PRIMARY KEY (wallet_id),
    CONSTRAINT uq_wallet_user   UNIQUE (user_id),
    CONSTRAINT chk_balance      CHECK (current_balance >= 0),
    CONSTRAINT chk_limit        CHECK (daily_limit > 0)
) ENGINE=InnoDB COMMENT='Wallet balances - one wallet per user';

CREATE INDEX idx_wallet_status ON wallets (wallet_status);


-- ============================================================
-- TABLE 4: agents
-- MoMo agents who handle cash in and cash out
-- ============================================================
CREATE TABLE agents (
    agent_id      INT          NOT NULL AUTO_INCREMENT,
    user_id       INT          NOT NULL COMMENT 'The user record for this agent',
    agent_code    VARCHAR(50)  NOT NULL COMMENT 'Official MTN agent code',
    business_name VARCHAR(100)     NULL COMMENT 'Name of the agent business',
    location      VARCHAR(100)     NULL COMMENT 'Where the agent is located',
    is_verified   TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1 means MTN has verified them',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_agents       PRIMARY KEY (agent_id),
    CONSTRAINT uq_agent_code   UNIQUE (agent_code)
) ENGINE=InnoDB COMMENT='Registered MoMo agents for cash in and cash out';

CREATE INDEX idx_agents_user     ON agents (user_id);
CREATE INDEX idx_agents_verified ON agents (is_verified);


-- ============================================================
-- TABLE 5: merchants
-- Businesses that accept MoMo payments
-- ============================================================
CREATE TABLE merchants (
    merchant_id        INT          NOT NULL AUTO_INCREMENT,
    user_id            INT          NOT NULL COMMENT 'The user record for this merchant',
    merchant_code      VARCHAR(50)  NOT NULL COMMENT 'Official MTN merchant code',
    business_name      VARCHAR(100) NOT NULL COMMENT 'Registered business name',
    business_category  VARCHAR(50)      NULL COMMENT 'What kind of business e.g RETAIL, FOOD',
    settlement_account VARCHAR(100)     NULL COMMENT 'Bank account where MoMo sends their money',
    is_verified        TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1 means MTN approved them',
    created_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_merchants     PRIMARY KEY (merchant_id),
    CONSTRAINT uq_merchant_code UNIQUE (merchant_code)
) ENGINE=InnoDB COMMENT='Registered merchants that receive MoMo payments';

CREATE INDEX idx_merchants_user     ON merchants (user_id);
CREATE INDEX idx_merchants_category ON merchants (business_category);


-- ============================================================
-- TABLE 6: sms_raw_messages
-- Every SMS we receive gets stored here before processing
-- ============================================================
CREATE TABLE sms_raw_messages (
    sms_id         INT          NOT NULL AUTO_INCREMENT,
    message_uid    VARCHAR(64)  NOT NULL COMMENT 'Unique hash to avoid processing same SMS twice',
    raw_body       TEXT         NOT NULL COMMENT 'The actual SMS text we received',
    parse_status   VARCHAR(10)  NOT NULL DEFAULT 'PENDING'
                                         COMMENT 'PENDING, SUCCESS, FAILED or SKIPPED',
    failure_reason VARCHAR(255)     NULL COMMENT 'Why it failed to parse if it did',
    received_at    DATETIME     NOT NULL COMMENT 'When we got the SMS',
    processed_at   DATETIME         NULL COMMENT 'When we tried to parse it',

    CONSTRAINT pk_sms        PRIMARY KEY (sms_id),
    CONSTRAINT uq_msg_uid    UNIQUE (message_uid),
    CONSTRAINT chk_body      CHECK (CHAR_LENGTH(TRIM(raw_body)) > 0)
) ENGINE=InnoDB COMMENT='Raw SMS messages before and after ETL processing';

CREATE INDEX idx_sms_status ON sms_raw_messages (parse_status);
CREATE INDEX idx_sms_date   ON sms_raw_messages (received_at);


-- ============================================================
-- TABLE 7: transactions
-- The main table - every MoMo transaction lives here
-- ============================================================
CREATE TABLE transactions (
    transaction_id          INT           NOT NULL AUTO_INCREMENT,
    sms_id                  INT               NULL COMMENT 'Which SMS created this transaction',
    reference_id            VARCHAR(50)   NOT NULL COMMENT 'MoMo reference number from the SMS',
    sender_id               INT           NOT NULL COMMENT 'Who sent the money',
    receiver_id             INT               NULL COMMENT 'Who received it (NULL for withdrawals)',
    agent_id                INT               NULL COMMENT 'Agent involved (only for withdrawals)',
    merchant_id             INT               NULL COMMENT 'Merchant involved (only for payments)',
    category_id             INT           NOT NULL COMMENT 'What type of transaction this is',
    reverses_transaction_id INT               NULL COMMENT 'If this is a reversal, which transaction it reverses',
    amount                  DECIMAL(15,2) NOT NULL COMMENT 'How much money moved in RWF',
    fee                     DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'MoMo fee charged',
    sender_balance_after    DECIMAL(15,2)     NULL COMMENT 'Senders balance right after this transaction',
    transaction_date        DATETIME      NOT NULL COMMENT 'When the transaction happened',
    status                  VARCHAR(10)   NOT NULL DEFAULT 'SUCCESS'
                                                   COMMENT 'SUCCESS, FAILED, PENDING or REVERSED',
    created_at              DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_transactions  PRIMARY KEY (transaction_id),
    CONSTRAINT uq_reference     UNIQUE (reference_id),
    CONSTRAINT chk_amount       CHECK (amount > 0),
    CONSTRAINT chk_fee          CHECK (fee >= 0),
    CONSTRAINT chk_bal_after    CHECK (sender_balance_after IS NULL
                                       OR sender_balance_after >= 0)
) ENGINE=InnoDB COMMENT='Central table holding every parsed MoMo transaction';

CREATE INDEX idx_txn_sender      ON transactions (sender_id);
CREATE INDEX idx_txn_receiver    ON transactions (receiver_id);
CREATE INDEX idx_txn_agent       ON transactions (agent_id);
CREATE INDEX idx_txn_merchant    ON transactions (merchant_id);
CREATE INDEX idx_txn_category    ON transactions (category_id);
CREATE INDEX idx_txn_sms         ON transactions (sms_id);
CREATE INDEX idx_txn_reversal    ON transactions (reverses_transaction_id);
CREATE INDEX idx_txn_date        ON transactions (transaction_date);
CREATE INDEX idx_txn_status      ON transactions (status);
CREATE INDEX idx_txn_date_status ON transactions (transaction_date, status);


-- ============================================================
-- TABLE 8: tags
-- Labels we put on transactions for analysis
-- ============================================================
CREATE TABLE tags (
    tag_id    INT         NOT NULL AUTO_INCREMENT,
    tag_name  VARCHAR(50) NOT NULL COMMENT 'Label name e.g high-value, flagged, suspicious',
    tag_color CHAR(7)     NOT NULL DEFAULT '#CCCCCC' COMMENT 'Hex color for the dashboard UI',

    CONSTRAINT pk_tags      PRIMARY KEY (tag_id),
    CONSTRAINT uq_tag_name  UNIQUE (tag_name),
    CONSTRAINT chk_color    CHECK (tag_color REGEXP '^#[0-9A-Fa-f]{6}$')
) ENGINE=InnoDB COMMENT='Labels that can be applied to transactions';


-- ============================================================
-- TABLE 9: transaction_tags (Junction table)
-- Connects transactions and tags - solves the many-to-many
-- ============================================================
CREATE TABLE transaction_tags (
    transaction_id INT         NOT NULL COMMENT 'Which transaction',
    tag_id         INT         NOT NULL COMMENT 'Which tag',
    tagged_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tagged_by      VARCHAR(50)     NULL COMMENT 'Who or what applied this tag',

    CONSTRAINT pk_txn_tags PRIMARY KEY (transaction_id, tag_id)
) ENGINE=InnoDB COMMENT='Junction table - resolves many-to-many between transactions and tags';


-- ============================================================
-- TABLE 10: system_logs
-- Everything the ETL pipeline does gets logged here
-- ============================================================
CREATE TABLE system_logs (
    log_id         INT          NOT NULL AUTO_INCREMENT,
    sms_id         INT              NULL COMMENT 'Related SMS if this log is about an SMS',
    transaction_id INT              NULL COMMENT 'Related transaction if there is one',
    triggered_by   INT              NULL COMMENT 'Which user caused this event if any',
    log_level      VARCHAR(10)  NOT NULL COMMENT 'DEBUG, INFO, WARNING, ERROR or CRITICAL',
    event_type     VARCHAR(50)  NOT NULL COMMENT 'Short code like PARSE_ERROR or DB_INSERT',
    message        TEXT         NOT NULL COMMENT 'Full description of what happened',
    source_file    VARCHAR(255)     NULL COMMENT 'Which Python file logged this',
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_logs          PRIMARY KEY (log_id),
    CONSTRAINT chk_log_message  CHECK (CHAR_LENGTH(TRIM(message)) > 0)
) ENGINE=InnoDB COMMENT='Audit trail for the ETL pipeline';

CREATE INDEX idx_logs_sms    ON system_logs (sms_id);
CREATE INDEX idx_logs_txn    ON system_logs (transaction_id);
CREATE INDEX idx_logs_user   ON system_logs (triggered_by);
CREATE INDEX idx_logs_level  ON system_logs (log_level);
CREATE INDEX idx_logs_type   ON system_logs (event_type);
CREATE INDEX idx_logs_date   ON system_logs (created_at);


-- ============================================================
-- FOREIGN KEY CONSTRAINTS
-- ============================================================

ALTER TABLE wallets
  ADD CONSTRAINT fk_wallets_user
    FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE agents
  ADD CONSTRAINT fk_agents_user
    FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE merchants
  ADD CONSTRAINT fk_merchants_user
    FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE transactions
  ADD CONSTRAINT fk_txn_sms
    FOREIGN KEY (sms_id) REFERENCES sms_raw_messages(sms_id)
    ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE transactions
  ADD CONSTRAINT fk_txn_sender
    FOREIGN KEY (sender_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE transactions
  ADD CONSTRAINT fk_txn_receiver
    FOREIGN KEY (receiver_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE transactions
  ADD CONSTRAINT fk_txn_agent
    FOREIGN KEY (agent_id) REFERENCES agents(agent_id)
    ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE transactions
  ADD CONSTRAINT fk_txn_merchant
    FOREIGN KEY (merchant_id) REFERENCES merchants(merchant_id)
    ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE transactions
  ADD CONSTRAINT fk_txn_category
    FOREIGN KEY (category_id) REFERENCES transaction_categories(category_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE transactions
  ADD CONSTRAINT fk_txn_reversal
    FOREIGN KEY (reverses_transaction_id) REFERENCES transactions(transaction_id)
    ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE transaction_tags
  ADD CONSTRAINT fk_tt_transaction
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE transaction_tags
  ADD CONSTRAINT fk_tt_tag
    FOREIGN KEY (tag_id) REFERENCES tags(tag_id)
    ON UPDATE CASCADE ON DELETE CASCADE;


-- ============================================================
-- SAMPLE DATA & TESTING (CRUD)
-- ============================================================

-- INSERT (Create)
INSERT INTO transaction_categories (category_name) VALUES ('P2P'), ('CASH_IN'), ('CASH_OUT');
INSERT INTO users (phone_number, full_name) VALUES ('+250780000001', 'Alice'), ('+250780000002', 'Bob'), ('+250780000005', 'Eve');

-- SELECT (Read)
SELECT * FROM users;

-- UPDATE (Update)
UPDATE users SET account_type = 'AGENT' WHERE full_name = 'Alice';

-- DELETE (Delete)
DELETE FROM users WHERE full_name = 'Eve';
