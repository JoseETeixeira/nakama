/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Catalog and Entitlements Migration
 *
 * Creates the catalog and entitlements tables for the in-game commerce system.
 * The catalog table stores the server-side inventory of purchasable items (cosmetics,
 * expansions, currency packs, battle passes, boosts) with SKU-based pricing, regional
 * availability, and time-limited offers. The entitlements table tracks player purchases
 * as durable, server-validated ownership records that persist across sessions and devices.
 *
 * Catalog Table Design:
 * - sku: VARCHAR(100) primary key - unique stock-keeping unit identifier (e.g., 'cosmetic_dragon_wings_001')
 * - name: VARCHAR(255) - human-readable display name for the store UI
 * - description: TEXT - marketing copy explaining the item's value and features
 * - price_usd: DECIMAL(10,2) - base price in USD (client converts to local currency via exchange rates)
 * - preview_url: TEXT - CDN URL for preview images/videos shown in store UI
 * - entitlements: JSONB - array of what the player receives upon purchase
 *   Format: [{type: 'cosmetic'|'currency'|'expansion'|'boost', itemId: string, quantity: number}, ...]
 *   Example: [{"type": "cosmetic", "itemId": "dragon_wings", "quantity": 1}, {"type": "currency", "itemId": "gems", "quantity": 100}]
 * - regions: TEXT[] - geographic availability filter (['us', 'eu', 'asia'], null = worldwide)
 * - available_from: TIMESTAMPTZ - when the item becomes available (null = always available)
 * - available_until: TIMESTAMPTZ - when the item expires (null = never expires, for limited-time offers)
 * - stock_limit: INT - maximum purchases across all players (null = unlimited, for exclusive items)
 *
 * Entitlements Table Design:
 * - entitlement_id: UUID primary key - unique identifier for each granted entitlement
 * - account_id: UUID foreign key - player who owns this entitlement (account-wide ownership)
 * - sku: VARCHAR(100) foreign key - references the catalog item that was purchased
 * - state: VARCHAR(20) - lifecycle state: 'active' (usable), 'expired' (time-limited boost ended), 'revoked' (refund/ban)
 * - purchase_date: TIMESTAMPTZ - when the entitlement was granted (for auditing and expiration calculations)
 * - receipt_id: VARCHAR(255) - platform-specific receipt identifier (Apple, Google, Steam) for purchase verification
 * - metadata: JSONB - additional context (platform, transaction_id, expiry_date for boosts, character_id for character-specific items)
 *
 * Commerce Workflow:
 *
 * 1. Player browses catalog:
 *    - Client requests catalog via RPC
 *    - Server filters by player region and current timestamp (available_from <= NOW() <= available_until)
 *    - Server excludes items where stock_limit reached or player already owns non-stackable items
 *    - Client displays catalog with prices, previews, descriptions
 *
 * 2. Player initiates purchase:
 *    - Client sends platform-specific purchase request (Apple/Google/Steam in-app purchase flow)
 *    - Platform processes payment and returns receipt
 *    - Client sends receipt to Nakama for verification
 *
 * 3. Server verifies purchase (Requirement 25):
 *    - Nakama validates receipt with platform API (Apple App Store, Google Play, Steam)
 *    - If valid and not duplicate, grants entitlements
 *    - Server creates entitlement record(s) in entitlements table (one per item in catalog.entitlements array)
 *    - Server credits soft currency to wallets table if entitlements include currency
 *    - Server logs purchase to audit_logs for fraud detection and compliance
 *    - Server sends success response to client with granted entitlements
 *
 * 4. Player uses entitlement (Requirement 26):
 *    - Player equips cosmetic → Server validates entitlement exists and state='active' → Broadcasts appearance to other clients
 *    - Player consumes boost → Server checks expiry, applies effect, updates state to 'expired' when time limit reached
 *    - Player accesses expansion content → Server validates entitlement for zone/feature access
 *
 * 5. Refund/revocation:
 *    - Platform processes refund → Nakama receives webhook notification
 *    - Server updates entitlement state to 'revoked'
 *    - Server unequips cosmetics from all characters
 *    - Server debits soft currency if applicable (negative wallet transaction)
 *    - Server logs revocation to audit_logs
 *
 * Regional Filtering and Time-Limited Offers:
 * - GIN index on catalog.regions enables fast array containment queries: WHERE 'us' = ANY(regions) OR regions IS NULL
 * - Available_from/until support flash sales, seasonal events, battle pass windows
 * - Stock_limit enables exclusive/limited edition items (e.g., first 1000 buyers get special cosmetic)
 *
 * Entitlement Lifecycle States:
 * - 'active': Normal state, entitlement is usable
 * - 'expired': Time-limited boost/subscription ended (e.g., 7-day XP boost completed)
 * - 'revoked': Purchase refunded or player banned from using the item
 *
 * Performance Considerations:
 * - GIN index on catalog.regions optimizes regional filtering for catalog queries
 * - idx_entitlements_account enables fast "show all items owned by player" queries
 * - idx_entitlements_state supports bulk queries for active entitlements and revocation workflows
 * - Foreign key on entitlements.sku enforces referential integrity (cannot grant non-existent items)
 * - Foreign key on entitlements.account_id with CASCADE delete ensures cleanup when accounts deleted
 *
 * Security and Fraud Prevention:
 * - Server-side receipt validation prevents forged purchases
 * - receipt_id uniqueness check (application-level) prevents duplicate entitlement grants from same receipt
 * - audit_logs integration tracks all purchase attempts (valid and invalid) for fraud detection
 * - State management supports revocation for chargebacks and banned accounts
 *
 * Requirements: Requirement 24 (Store Catalog), Requirement 25 (Purchase Verification), Requirement 26 (Entitlements and Cosmetics)
 * Design Reference: Data Models section - Catalog and Entitlements Tables (lines 690-724)
 * Related: Commerce Service (component #10), Wallets Table (task 1.1.14)
 * Task: 1.1.13 - Create catalog and entitlements tables migration
 */

-- +migrate Up

-- Catalog table for in-game store inventory
-- Stores SKUs with pricing, regional availability, time-limited offers, and entitlement definitions
CREATE TABLE catalog (
  sku VARCHAR(100) PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  price_usd DECIMAL(10, 2),
  preview_url TEXT,
  entitlements JSONB, -- array of {type, itemId, quantity}
  regions TEXT[], -- ['us', 'eu', 'asia'], null = all regions
  available_from TIMESTAMPTZ,
  available_until TIMESTAMPTZ,
  stock_limit INT -- null = unlimited
);

-- GIN index for efficient regional filtering queries (WHERE 'us' = ANY(regions))
CREATE INDEX idx_catalog_regions ON catalog USING GIN(regions);

-- Entitlements table for player purchase records
-- Tracks durable ownership of cosmetics, expansions, boosts with state management for refunds/bans
CREATE TABLE entitlements (
  entitlement_id UUID PRIMARY KEY,
  account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
  sku VARCHAR(100) REFERENCES catalog(sku),
  state VARCHAR(20) DEFAULT 'active', -- 'active', 'expired', 'revoked'
  purchase_date TIMESTAMPTZ DEFAULT NOW(),
  receipt_id VARCHAR(255),
  metadata JSONB
);

-- Index for fast "show all items owned by this player" queries
CREATE INDEX idx_entitlements_account ON entitlements(account_id);

-- Index for filtering active/expired/revoked entitlements
CREATE INDEX idx_entitlements_state ON entitlements(state);

-- Table and column comments for documentation
COMMENT ON TABLE catalog IS 'In-game store inventory with SKU-based pricing, regional availability, time-limited offers, and entitlement definitions for cosmetics, expansions, currency packs, and boosts';
COMMENT ON COLUMN catalog.sku IS 'Stock-keeping unit - unique identifier for catalog items (e.g., cosmetic_dragon_wings_001, expansion_dungeon_pack_v2)';
COMMENT ON COLUMN catalog.name IS 'Human-readable display name shown in store UI';
COMMENT ON COLUMN catalog.description IS 'Marketing copy explaining the item''s value, features, and contents';
COMMENT ON COLUMN catalog.price_usd IS 'Base price in USD - client converts to local currency via exchange rates';
COMMENT ON COLUMN catalog.preview_url IS 'CDN URL for preview images/videos displayed in store UI';
COMMENT ON COLUMN catalog.entitlements IS 'JSONB array defining what player receives: [{type: "cosmetic"|"currency"|"expansion"|"boost", itemId: string, quantity: number}, ...]';
COMMENT ON COLUMN catalog.regions IS 'Geographic availability filter - TEXT array like [''us'', ''eu'', ''asia''], null means worldwide availability';
COMMENT ON COLUMN catalog.available_from IS 'When item becomes purchasable (null = always available) - supports scheduled releases';
COMMENT ON COLUMN catalog.available_until IS 'When item expires (null = never expires) - supports flash sales and limited-time offers';
COMMENT ON COLUMN catalog.stock_limit IS 'Maximum purchases across all players (null = unlimited) - enables exclusive/limited edition items';

COMMENT ON TABLE entitlements IS 'Player purchase records tracking durable ownership of cosmetics, expansions, boosts - persists across sessions and devices with state management for refunds/bans';
COMMENT ON COLUMN entitlements.entitlement_id IS 'UUID primary key - unique identifier for each granted entitlement';
COMMENT ON COLUMN entitlements.account_id IS 'Foreign key to accounts - player who owns this entitlement (account-wide ownership)';
COMMENT ON COLUMN entitlements.sku IS 'Foreign key to catalog - references the purchased item';
COMMENT ON COLUMN entitlements.state IS 'Lifecycle state: ''active'' (usable), ''expired'' (time-limited boost ended), ''revoked'' (refunded/banned)';
COMMENT ON COLUMN entitlements.purchase_date IS 'When entitlement was granted - used for auditing and expiration calculations for time-limited boosts';
COMMENT ON COLUMN entitlements.receipt_id IS 'Platform-specific receipt identifier (Apple, Google, Steam) for purchase verification and duplicate detection';
COMMENT ON COLUMN entitlements.metadata IS 'JSONB context: platform, transaction_id, expiry_date for boosts, character_id for character-specific items';

-- +migrate Down

DROP TABLE IF EXISTS entitlements;
DROP TABLE IF EXISTS catalog;
