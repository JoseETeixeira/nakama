/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Wallets and Wallet Transactions Migration
 *
 * Creates the wallets and wallet_transactions tables for soft currency management.
 * The wallets table stores multi-currency balances (gold, gems, event tokens) with
 * optimistic locking to prevent lost updates during concurrent operations. The
 * wallet_transactions table provides an append-only audit log of all credits and
 * debits with balance snapshots for reconciliation, dispute resolution, and fraud
 * detection.
 *
 * Wallets Table Design:
 * - account_id: UUID primary key and foreign key - one wallet per account
 * - balances: JSONB storing multiple currency types with flexible schema
 *   Format: {"gold": 1000, "gems": 50, "event_tokens": 10, "battle_pass_points": 250}
 *   Supports arbitrary currency types without schema migrations
 * - version: INT for optimistic locking - increments on every wallet update
 *   Prevents lost updates when multiple operations modify wallet concurrently
 *
 * Wallet Transactions Table Design:
 * - transaction_id: BIGSERIAL primary key - auto-incrementing for high-volume writes
 * - account_id: UUID foreign key - player who earned/spent currency
 * - currency: VARCHAR(50) - currency type identifier (gold, gems, event_tokens, etc.)
 * - amount: BIGINT - transaction delta (positive for credits, negative for debits)
 *   Example: +100 for quest reward, -50 for vendor purchase
 * - balance_after: BIGINT - currency balance snapshot AFTER this transaction
 *   Enables fast balance reconciliation and integrity checks without replaying all transactions
 * - source: VARCHAR(100) - transaction origin for auditing and analytics
 *   Examples: 'quest_reward', 'vendor_sell', 'purchase', 'refund', 'gm_grant', 'event_bonus'
 * - timestamp: TIMESTAMPTZ - when transaction occurred (auto-generated)
 *
 * Atomic Wallet Operations (Requirement 27):
 *
 * 1. Credit Currency (Earning):
 *    BEGIN TRANSACTION;
 *      -- Read current wallet with version
 *      SELECT balances, version FROM wallets WHERE account_id = $1 FOR UPDATE;
 *
 *      -- Calculate new balance
 *      new_balance = current_balance + credit_amount;
 *
 *      -- Update wallet with optimistic lock check
 *      UPDATE wallets
 *      SET balances = jsonb_set(balances, '{gold}', new_balance::text::jsonb),
 *          version = version + 1
 *      WHERE account_id = $1 AND version = $expected_version;
 *
 *      -- If affected rows = 0, version mismatch detected → retry
 *
 *      -- Log transaction with balance snapshot
 *      INSERT INTO wallet_transactions (account_id, currency, amount, balance_after, source)
 *      VALUES ($1, 'gold', 100, new_balance, 'quest_reward');
 *    COMMIT;
 *
 * 2. Debit Currency (Spending):
 *    BEGIN TRANSACTION;
 *      -- Read and lock wallet
 *      SELECT balances, version FROM wallets WHERE account_id = $1 FOR UPDATE;
 *
 *      -- Verify sufficient balance
 *      IF current_balance < debit_amount THEN
 *        ROLLBACK; -- Insufficient funds
 *      END IF;
 *
 *      -- Calculate new balance
 *      new_balance = current_balance - debit_amount;
 *
 *      -- Update wallet
 *      UPDATE wallets
 *      SET balances = jsonb_set(balances, '{gold}', new_balance::text::jsonb),
 *          version = version + 1
 *      WHERE account_id = $1 AND version = $expected_version;
 *
 *      -- Log transaction (negative amount for debit)
 *      INSERT INTO wallet_transactions (account_id, currency, amount, balance_after, source)
 *      VALUES ($1, 'gold', -50, new_balance, 'vendor_purchase');
 *    COMMIT;
 *
 * Optimistic Locking Strategy:
 * The version column prevents lost updates in concurrent scenarios:
 * - Transaction A reads wallet (version=1, balance=100)
 * - Transaction B reads wallet (version=1, balance=100)
 * - Transaction A credits +50, updates version to 2 → SUCCESS
 * - Transaction B tries to debit -30, checks version=1 → FAILS (current version is 2)
 * - Transaction B retries with fresh read (version=2, balance=150) → SUCCESS
 *
 * Without optimistic locking, both transactions would operate on stale balance=100,
 * potentially causing incorrect final balance or negative balances.
 *
 * Audit Trail and Reconciliation:
 * The wallet_transactions table enables:
 * - Balance verification: SELECT SUM(amount) FROM wallet_transactions WHERE account_id = X AND currency = 'gold'
 *   Should equal current wallets.balances->>'gold'
 * - Dispute resolution: "Player claims they lost 100 gems" → Query transaction history
 * - Analytics: Revenue tracking, currency velocity, inflation monitoring
 * - Fraud detection: Sudden large credits from unexpected sources
 * - Rollback support: Reverse transactions by inserting compensating entries (negative of original)
 *
 * Transaction Source Categories:
 * - Earning: 'quest_reward', 'achievement', 'daily_login', 'event_bonus', 'loot_drop'
 * - Spending: 'vendor_purchase', 'repair', 'fast_travel', 'respawn_fee', 'crafting'
 * - Trading: 'player_trade_send', 'player_trade_receive', 'auction_sale', 'auction_bid'
 * - Commerce: 'iap_purchase', 'refund', 'chargeback'
 * - Admin: 'gm_grant', 'compensation', 'ban_confiscation'
 *
 * Performance Considerations:
 * - JSONB balances enable flexible currency types without ALTER TABLE
 * - BIGSERIAL transaction_id optimized for high-volume append-only writes
 * - idx_wallet_txn_account_time enables fast queries: "Show my last 100 transactions"
 * - balance_after column eliminates need to SUM all transactions for current balance
 * - Optimistic locking avoids expensive row-level locks (FOR UPDATE only during write)
 *
 * Multi-Currency Support:
 * The JSONB balances column supports arbitrary currencies:
 * - Hard currency (premium): gems, crystals
 * - Soft currency (earnable): gold, silver
 * - Event-specific: halloween_tokens, winter_coins, raid_points
 * - Battle pass: season_xp, premium_tokens
 * - No schema changes needed to add new currencies
 *
 * Integration with Commerce:
 * - Catalog entitlements can grant currency: entitlements=[{type:'currency', itemId:'gems', quantity:100}]
 * - Purchase verification credits wallet via wallet_transactions (source='iap_purchase')
 * - Refunds debit wallet via compensating transaction (source='refund', negative amount)
 *
 * Requirements: Requirement 27 (Soft Currency and Wallets)
 * Design Reference: Data Models section - Wallets and Wallet Transactions Tables (lines 724-744)
 * Related: Commerce Service (component #10), Catalog/Entitlements (task 1.1.13)
 * Task: 1.1.14 - Create wallets and wallet_transactions tables migration
 */

-- +migrate Up

-- Wallets table for multi-currency balances with optimistic locking
-- Stores soft currency (gold, gems, tokens) with versioning to prevent concurrent update conflicts
CREATE TABLE wallets (
  account_id UUID PRIMARY KEY REFERENCES accounts(account_id) ON DELETE CASCADE,
  balances JSONB, -- {gold: 1000, gems: 50, event_tokens: 10}
  version INT DEFAULT 1 -- for optimistic locking
);

-- Wallet Transactions table for immutable audit log of all currency operations
-- Provides double-entry bookkeeping with balance snapshots for reconciliation
CREATE TABLE wallet_transactions (
  transaction_id BIGSERIAL PRIMARY KEY,
  account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
  currency VARCHAR(50) NOT NULL,
  amount BIGINT NOT NULL, -- can be negative for debits
  balance_after BIGINT NOT NULL,
  source VARCHAR(100), -- 'quest_reward', 'vendor_sell', 'purchase', etc.
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Composite index for account-centric transaction history queries
-- Enables fast lookups: "Show all transactions for this player in time range"
CREATE INDEX idx_wallet_txn_account_time ON wallet_transactions(account_id, timestamp);

-- Table and column comments for documentation
COMMENT ON TABLE wallets IS 'Multi-currency wallet balances per account with optimistic locking - supports gold, gems, event tokens, and arbitrary soft currencies via JSONB';
COMMENT ON COLUMN wallets.account_id IS 'UUID primary key and foreign key - one wallet per account, cascades delete when account removed';
COMMENT ON COLUMN wallets.balances IS 'JSONB multi-currency balances: {"gold": 1000, "gems": 50, "event_tokens": 10} - flexible schema for arbitrary currency types';
COMMENT ON COLUMN wallets.version IS 'Optimistic locking version number - increments on every wallet update to prevent lost updates during concurrent operations';

COMMENT ON TABLE wallet_transactions IS 'Append-only audit log of all currency credits and debits - provides reconciliation, dispute resolution, and fraud detection';
COMMENT ON COLUMN wallet_transactions.transaction_id IS 'BIGSERIAL primary key - auto-incrementing for high-volume append-only writes';
COMMENT ON COLUMN wallet_transactions.account_id IS 'Foreign key to accounts - player who earned/spent currency';
COMMENT ON COLUMN wallet_transactions.currency IS 'Currency type identifier: gold, gems, event_tokens, battle_pass_points, etc.';
COMMENT ON COLUMN wallet_transactions.amount IS 'Transaction delta - positive for credits (earning), negative for debits (spending)';
COMMENT ON COLUMN wallet_transactions.balance_after IS 'Currency balance snapshot AFTER this transaction - enables fast reconciliation without replaying all transactions';
COMMENT ON COLUMN wallet_transactions.source IS 'Transaction origin for auditing: quest_reward, vendor_purchase, iap_purchase, gm_grant, refund, etc.';
COMMENT ON COLUMN wallet_transactions.timestamp IS 'When transaction occurred - auto-generated, indexed for time-range queries';

-- +migrate Down

DROP TABLE IF EXISTS wallet_transactions;
DROP TABLE IF EXISTS wallets;
