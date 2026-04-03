-- ============================================================
-- MoMo SMS Analytics Dashboard - Database Setup
-- Team: Yellow
-- Week 2 - Database Design and Implementation
-- ============================================================

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
    agent_id                INT               NULL COMMENT 'Agent involved (only for withdrawals/deposits)',
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
-- Added after all tables exist to avoid ordering issues
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
-- SAMPLE DATA
-- Realistic data covering all 10 tables (5+ rows per table)
-- Scenario: 10 users, 3 agents, 3 merchants, 12 SMS messages,
--           10 transactions, 5 tags, multiple logs
-- ============================================================

-- ----------------------------
-- 1. transaction_categories (10 rows - one per MoMo type)
-- ----------------------------
INSERT INTO transaction_categories (category_name, description, requires_agent, requires_merchant) VALUES
  ('DEPOSIT',          'Cash deposited into wallet via an agent',            1, 0),
  ('WITHDRAWAL',       'Cash withdrawn from wallet via an agent',            1, 0),
  ('PEER_TRANSFER',    'Sending money directly to another person',           0, 0),
  ('MERCHANT_PAYMENT', 'Payment made to a registered business',              0, 1),
  ('BILL_PAYMENT',     'Paying a utility or service bill',                   0, 0),
  ('AIRTIME_PURCHASE', 'Buying airtime for self or another number',          0, 0),
  ('BANK_TRANSFER',    'Transfer from MoMo wallet to a bank account',        0, 0),
  ('REVERSAL',         'Reversal of a previously completed transaction',     0, 0),
  ('BUNDLE_PURCHASE',  'Buying an internet or voice bundle',                 0, 0),
  ('THIRD_PARTY_TXN',  'Payment initiated by a third-party app or service',  0, 0);


-- ----------------------------
-- 2. users (10 rows: 4 personal, 3 agents, 3 merchants)
-- ----------------------------
INSERT INTO users (phone_number, full_name, account_type, is_active) VALUES
  ('+250781001001', 'Amina Uwimana',      'PERSONAL',  1),  -- user_id 1
  ('+250782002002', 'Olivier Nkurunziza', 'PERSONAL',  1),  -- user_id 2
  ('+250783003003', 'Chantal Mukamana',   'PERSONAL',  1),  -- user_id 3
  ('+250784004004', 'Jean-Paul Habimana', 'PERSONAL',  1),  -- user_id 4
  ('+250785005005', 'Diane Ingabire',     'PERSONAL',  1),  -- user_id 5
  ('+250786006006', 'Pascal Niyonzima',   'AGENT',     1),  -- user_id 6
  ('+250787007007', 'Vestine Tuyisenge',  'AGENT',     1),  -- user_id 7
  ('+250788008008', 'Fidele Uwayo',       'AGENT',     1),  -- user_id 8
  ('+250789009009', 'Kigali SuperMart',   'MERCHANT',  1),  -- user_id 9
  ('+250780010010', 'Remera Pharmacy',    'MERCHANT',  1),  -- user_id 10
  ('+250780011011', 'Nyamirambo Café',    'MERCHANT',  1);  -- user_id 11


-- ----------------------------
-- 3. wallets (one per user - 11 rows)
-- ----------------------------
INSERT INTO wallets (user_id, current_balance, daily_limit, wallet_status, last_transaction_at) VALUES
  (1,  52000.00,  10000000.00, 'ACTIVE',  '2024-03-06 07:30:00'),
  (2,  18750.00,  10000000.00, 'ACTIVE',  '2024-03-06 07:30:00'),
  (3, 130000.00,  10000000.00, 'ACTIVE',  '2024-03-05 14:00:00'),
  (4,  87100.00,  10000000.00, 'ACTIVE',  '2024-03-07 09:45:00'),
  (5,   3200.00,  10000000.00, 'ACTIVE',  '2024-03-08 11:20:00'),
  (6, 450000.00,  50000000.00, 'ACTIVE',  '2024-03-08 08:00:00'),
  (7, 312000.00,  50000000.00, 'ACTIVE',  '2024-03-07 16:00:00'),
  (8, 275000.00,  50000000.00, 'FROZEN',  '2024-03-04 10:00:00'),
  (9, 980000.00,  50000000.00, 'ACTIVE',  '2024-03-09 13:15:00'),
 (10, 210000.00,  50000000.00, 'ACTIVE',  '2024-03-08 15:30:00'),
 (11, 155000.00,  50000000.00, 'ACTIVE',  '2024-03-09 12:00:00');


-- ----------------------------
-- 4. agents (3 verified agents)
-- ----------------------------
INSERT INTO agents (user_id, agent_code, business_name, location, is_verified) VALUES
  (6, 'AGT-KGL-00601', 'Pascal MoMo Hub',       'Kigali, Gasabo, Kimironko',   1),
  (7, 'AGT-KGL-00702', 'Vestine Cash Point',     'Kigali, Nyarugenge, Nyabugogo', 1),
  (8, 'AGT-KGL-00803', 'Fidele Mobile Services', 'Kigali, Kicukiro, Gikondo',   0);


-- ----------------------------
-- 5. merchants (3 verified merchants)
-- ----------------------------
INSERT INTO merchants (user_id, merchant_code, business_name, business_category, settlement_account, is_verified) VALUES
  (9,  'MRC-KGL-09911', 'Kigali SuperMart',  'RETAIL',    'BK-RW-00991100', 1),
  (10, 'MRC-KGL-10022', 'Remera Pharmacy',   'HEALTH',    'BK-RW-01002200', 1),
  (11, 'MRC-KGL-11133', 'Nyamirambo Café',   'FOOD',      'BK-RW-01113300', 1);


-- ----------------------------
-- 6. sms_raw_messages (12 rows: 10 success, 1 failed, 1 skipped)
-- ----------------------------
INSERT INTO sms_raw_messages (message_uid, raw_body, parse_status, failure_reason, received_at, processed_at) VALUES
  ('hash001', 'TxId: TXN-001. You have sent 8,000 RWF to Olivier Nkurunziza 0782002002. Fee: 80 RWF. Balance: 43,920 RWF. Date: 01/03/2024.',                      'SUCCESS', NULL,                                             '2024-03-01 09:10:00', '2024-03-01 09:10:05'),
  ('hash002', 'TxId: TXN-002. You have received 30,000 RWF from Agent Pascal Niyonzima (AGT-KGL-00601). Balance: 73,920 RWF. Date: 02/03/2024.',                   'SUCCESS', NULL,                                             '2024-03-02 10:00:00', '2024-03-02 10:00:04'),
  ('hash003', 'TxId: TXN-003. You have sent 15,000 RWF to Chantal Mukamana 0783003003. Fee: 100 RWF. Balance: 58,820 RWF. Date: 03/03/2024.',                      'SUCCESS', NULL,                                             '2024-03-03 08:30:00', '2024-03-03 08:30:06'),
  ('hash004', 'TxId: TXN-004. Payment of 4,800 RWF to WASAC (Water bill). Fee: 0 RWF. Balance: 54,020 RWF. Date: 04/03/2024.',                                    'SUCCESS', NULL,                                             '2024-03-04 11:00:00', '2024-03-04 11:00:03'),
  ('hash005', 'TxId: TXN-005. You bought 2,000 RWF airtime for 0781001001. Balance: 52,020 RWF. Date: 05/03/2024.',                                                'SUCCESS', NULL,                                             '2024-03-05 07:45:00', '2024-03-05 07:45:02'),
  ('hash006', 'TxId: TXN-006. You have withdrawn 10,000 RWF via Agent Vestine Tuyisenge (AGT-KGL-00702). Fee: 100 RWF. Balance: 41,920 RWF. Date: 06/03/2024.',   'SUCCESS', NULL,                                             '2024-03-06 07:30:00', '2024-03-06 07:30:04'),
  ('hash007', 'TxId: TXN-007. Payment of 5,000 RWF to Kigali SuperMart (MRC-KGL-09911). Fee: 0 RWF. Balance: 36,920 RWF. Date: 07/03/2024.',                      'SUCCESS', NULL,                                             '2024-03-07 09:45:00', '2024-03-07 09:45:03'),
  ('hash008', 'TxId: TXN-008. Payment of 3,500 RWF to Remera Pharmacy (MRC-KGL-10022). Fee: 0 RWF. Balance: 33,420 RWF. Date: 08/03/2024.',                       'SUCCESS', NULL,                                             '2024-03-08 11:20:00', '2024-03-08 11:20:03'),
  ('hash009', 'TxId: TXN-009. You have sent 25,000 RWF to Jean-Paul Habimana 0784004004. Fee: 200 RWF. Balance: 8,220 RWF. Date: 09/03/2024.',                     'SUCCESS', NULL,                                             '2024-03-09 13:00:00', '2024-03-09 13:00:05'),
  ('hash010', 'TxId: TXN-010. Bank transfer of 60,000 RWF to BK account BK-RW-11223344. Fee: 300 RWF. Balance: 87,100 RWF. Date: 10/03/2024.',                    'SUCCESS', NULL,                                             '2024-03-10 08:00:00', '2024-03-10 08:00:06'),
  ('hash011', 'MTN MoMo Alert: Trnsfer cmplete Amt:?? Ref no: N/A [MSG CORRUPTED]',                                                                                'FAILED',  'Amount field missing or corrupted in SMS body',  '2024-03-10 10:30:00', '2024-03-10 10:30:03'),
  ('hash012', 'MTN: Your account has been verified. Welcome to MoMo. Reply HELP for help.',                                                                        'SKIPPED', 'Non-transaction SMS (system notification)',       '2024-03-11 06:00:00', '2024-03-11 06:00:01');


-- ----------------------------
-- 7. transactions (10 rows covering all major categories)
-- ----------------------------
INSERT INTO transactions (sms_id, reference_id, sender_id, receiver_id, agent_id, merchant_id, category_id, amount, fee, sender_balance_after, transaction_date, status) VALUES
  (1,  'TXN-001', 1, 2,    NULL, NULL, 3, 8000.00,  80.00, 43920.00, '2024-03-01 09:10:00', 'SUCCESS'),  -- Peer transfer: Amina -> Olivier
  (2,  'TXN-002', 1, 1,       1, NULL, 1, 30000.00,  0.00, 73920.00, '2024-03-02 10:00:00', 'SUCCESS'),  -- Deposit: Amina at Pascal's agent
  (3,  'TXN-003', 1, 3,    NULL, NULL, 3, 15000.00, 100.00, 58820.00, '2024-03-03 08:30:00', 'SUCCESS'),  -- Peer transfer: Amina -> Chantal
  (4,  'TXN-004', 1, NULL, NULL, NULL, 5,  4800.00,   0.00, 54020.00, '2024-03-04 11:00:00', 'SUCCESS'),  -- Bill payment: Amina pays water bill
  (5,  'TXN-005', 1, NULL, NULL, NULL, 6,  2000.00,   0.00, 52020.00, '2024-03-05 07:45:00', 'SUCCESS'),  -- Airtime: Amina buys airtime
  (6,  'TXN-006', 1, NULL,    2, NULL, 2, 10000.00, 100.00, 41920.00, '2024-03-06 07:30:00', 'SUCCESS'),  -- Withdrawal: Amina at Vestine's agent
  (7,  'TXN-007', 4, NULL, NULL,    1, 4,  5000.00,   0.00, 87100.00, '2024-03-07 09:45:00', 'SUCCESS'),  -- Merchant payment: Jean-Paul at SuperMart
  (8,  'TXN-008', 5, NULL, NULL,    2, 4,  3500.00,   0.00,  3200.00, '2024-03-08 11:20:00', 'SUCCESS'),  -- Merchant payment: Diane at Pharmacy
  (9,  'TXN-009', 3, 4,    NULL, NULL, 3, 25000.00, 200.00,  8220.00, '2024-03-09 13:00:00', 'SUCCESS'),  -- Peer transfer: Chantal -> Jean-Paul
  (10, 'TXN-010', 4, NULL, NULL, NULL, 7, 60000.00, 300.00, 27100.00, '2024-03-10 08:00:00', 'SUCCESS');  -- Bank transfer: Jean-Paul


-- ----------------------------
-- 8. tags (5 labels for analysis)
-- ----------------------------
INSERT INTO tags (tag_name, tag_color) VALUES
  ('high-value',   '#E74C3C'),   -- tag_id 1 : transaction above 20,000 RWF
  ('flagged',      '#E67E22'),   -- tag_id 2 : needs manual review
  ('reconciled',   '#2980B9'),   -- tag_id 3 : verified and matched
  ('first-txn',    '#27AE60'),   -- tag_id 4 : user's first ever transaction
  ('agent-assisted','#8E44AD');  -- tag_id 5 : required an agent


-- ----------------------------
-- 9. transaction_tags (M:N junction - multiple tags per transaction)
-- ----------------------------
INSERT INTO transaction_tags (transaction_id, tag_id, tagged_by) VALUES
  (1,  3, 'etl_pipeline'),   -- TXN-001 reconciled
  (1,  4, 'etl_pipeline'),   -- TXN-001 first-txn for Amina
  (2,  5, 'etl_pipeline'),   -- TXN-002 agent-assisted
  (2,  3, 'etl_pipeline'),   -- TXN-002 reconciled
  (6,  5, 'etl_pipeline'),   -- TXN-006 agent-assisted
  (9,  1, 'etl_pipeline'),   -- TXN-009 high-value (25,000 RWF)
  (9,  3, 'etl_pipeline'),   -- TXN-009 reconciled
  (10, 1, 'etl_pipeline'),   -- TXN-010 high-value (60,000 RWF)
  (10, 2, 'analyst_admin');  -- TXN-010 flagged for review


-- ----------------------------
-- 10. system_logs (10 rows covering INFO, WARNING, ERROR)
-- ----------------------------
INSERT INTO system_logs (sms_id, transaction_id, triggered_by, log_level, event_type, message, source_file) VALUES
  (1,  1,    NULL, 'INFO',    'DB_INSERT',    'Transaction TXN-001 inserted successfully.',                                         'load_db.py'),
  (2,  2,    NULL, 'INFO',    'DB_INSERT',    'Transaction TXN-002 (DEPOSIT) inserted. Wallet for user_id=1 updated.',              'load_db.py'),
  (3,  3,    NULL, 'INFO',    'DB_INSERT',    'Transaction TXN-003 inserted successfully.',                                         'load_db.py'),
  (4,  4,    NULL, 'INFO',    'DB_INSERT',    'Transaction TXN-004 (BILL_PAYMENT) inserted successfully.',                          'load_db.py'),
  (5,  5,    NULL, 'INFO',    'DB_INSERT',    'Transaction TXN-005 (AIRTIME_PURCHASE) inserted successfully.',                      'load_db.py'),
  (6,  6,    NULL, 'INFO',    'DB_INSERT',    'Transaction TXN-006 (WITHDRAWAL) inserted. Agent AGT-KGL-00702 recorded.',           'load_db.py'),
  (9,  9,    NULL, 'WARNING', 'HIGH_VALUE',   'Transaction TXN-009 exceeds 20,000 RWF threshold. Tagged as high-value.',           'categorize.py'),
  (10, 10,   NULL, 'WARNING', 'HIGH_VALUE',   'Transaction TXN-010 is 60,000 RWF bank transfer. Tagged as high-value and flagged.', 'categorize.py'),
  (11, NULL, NULL, 'ERROR',   'PARSE_ERROR',  'Could not parse SMS hash011. Amount field missing or corrupted. Moved to dead_letter.', 'parse_xml.py'),
  (12, NULL, NULL, 'INFO',    'SMS_SKIPPED',  'SMS hash012 identified as system notification. Skipped - no transaction created.',   'parse_xml.py');


-- ============================================================
-- CRUD OPERATIONS - Read queries to verify the data
-- ============================================================

-- ----------------------------
-- READ 1: All users and their wallet balances
-- ----------------------------
SELECT
    u.user_id,
    u.full_name,
    u.phone_number,
    u.account_type,
    w.current_balance,
    w.wallet_status
FROM users u
JOIN wallets w ON u.user_id = w.user_id
ORDER BY w.current_balance DESC;

-- ----------------------------
-- READ 2: All transactions with category and sender name
-- ----------------------------
SELECT
    t.transaction_id,
    t.reference_id,
    u.full_name        AS sender,
    tc.category_name,
    t.amount,
    t.fee,
    t.status,
    t.transaction_date
FROM transactions t
JOIN users u                    ON t.sender_id   = u.user_id
JOIN transaction_categories tc  ON t.category_id = tc.category_id
ORDER BY t.transaction_date;

-- ----------------------------
-- READ 3: SMS pipeline summary (parse_status counts)
-- ----------------------------
SELECT
    parse_status,
    COUNT(*) AS total
FROM sms_raw_messages
GROUP BY parse_status;

-- ----------------------------
-- READ 4: High-value transactions (tagged 'high-value')
-- ----------------------------
SELECT
    t.reference_id,
    u.full_name   AS sender,
    tc.category_name,
    t.amount,
    t.transaction_date
FROM transactions t
JOIN transaction_tags tt        ON t.transaction_id = tt.transaction_id
JOIN tags tg                    ON tt.tag_id        = tg.tag_id
JOIN users u                    ON t.sender_id      = u.user_id
JOIN transaction_categories tc  ON t.category_id    = tc.category_id
WHERE tg.tag_name = 'high-value'
ORDER BY t.amount DESC;

-- ----------------------------
-- READ 5: Analytics summary - total volume and fees per category
-- ----------------------------
SELECT
    tc.category_name,
    COUNT(t.transaction_id) AS num_transactions,
    SUM(t.amount)           AS total_volume_rwf,
    SUM(t.fee)              AS total_fees_rwf
FROM transactions t
JOIN transaction_categories tc ON t.category_id = tc.category_id
WHERE t.status = 'SUCCESS'
GROUP BY tc.category_name
ORDER BY total_volume_rwf DESC;

-- ----------------------------
-- UPDATE: Freeze a wallet flagged for review
-- ----------------------------
UPDATE wallets
SET wallet_status = 'FROZEN'
WHERE user_id = (SELECT user_id FROM users WHERE phone_number = '+250784004004');

-- Verify the update
SELECT u.full_name, w.wallet_status
FROM users u JOIN wallets w ON u.user_id = w.user_id
WHERE u.phone_number = '+250784004004';

-- ----------------------------
-- DELETE: Remove a test/placeholder tag (safe - no transactions use tag_id 5 in this demo)
-- Then re-insert it cleanly
-- ----------------------------
DELETE FROM tags WHERE tag_name = 'agent-assisted';
INSERT INTO tags (tag_name, tag_color) VALUES ('agent-assisted', '#8E44AD');