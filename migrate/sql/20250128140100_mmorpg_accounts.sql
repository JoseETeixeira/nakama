/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Accounts Migration
 *
 * Creates the accounts table for MMORPG multi-character authentication.
 * This table stores player credentials and serves as the parent table for
 * the characters table (task 1.1.3).
 *
 * Requirements: Requirement 1 (Player Authentication)
 * Design Reference: Data Models section - Accounts Table (lines 507-522)
 * Task: 1.1.2 - Create accounts table migration
 */

-- +migrate Up

-- Accounts table for MMORPG authentication
-- Supports multi-character accounts with device, email, and platform auth
CREATE TABLE accounts (
  account_id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE,
  password_hash BYTEA, -- bcrypt hash for email authentication
  device_id VARCHAR(255),
  apple_id VARCHAR(255), -- Apple Sign In ID
  google_id VARCHAR(255), -- Google Play Games ID
  steam_id VARCHAR(255), -- Steam ID
  platform_token TEXT, -- Generic platform token for other platforms
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  permissions TEXT[], -- ['player', 'gm', 'admin']
  banned BOOLEAN DEFAULT FALSE
);

-- Index for email-based authentication lookups
CREATE INDEX idx_accounts_email ON accounts(email);

-- Index for device ID authentication lookups
CREATE INDEX idx_accounts_device ON accounts(device_id);

-- Index for Apple ID authentication lookups
CREATE INDEX idx_accounts_apple ON accounts(apple_id);

-- Index for Google ID authentication lookups
CREATE INDEX idx_accounts_google ON accounts(google_id);

-- Index for Steam ID authentication lookups
CREATE INDEX idx_accounts_steam ON accounts(steam_id);

-- Table comment for documentation
COMMENT ON TABLE accounts IS 'MMORPG player accounts supporting multi-character management and multiple authentication methods';
COMMENT ON COLUMN accounts.account_id IS 'Unique account identifier used in JWT tokens';
COMMENT ON COLUMN accounts.email IS 'Email-based authentication (optional, nullable)';
COMMENT ON COLUMN accounts.password_hash IS 'bcrypt hash of password for email authentication (nullable, only set when email auth is used)';
COMMENT ON COLUMN accounts.device_id IS 'Device ID authentication for mobile/console (optional, nullable)';
COMMENT ON COLUMN accounts.apple_id IS 'Apple Sign In unique identifier (optional, nullable)';
COMMENT ON COLUMN accounts.google_id IS 'Google Play Games unique identifier (optional, nullable)';
COMMENT ON COLUMN accounts.steam_id IS 'Steam unique identifier (optional, nullable)';
COMMENT ON COLUMN accounts.platform_token IS 'Platform-specific token (Steam, Epic, etc.) for authentication';
COMMENT ON COLUMN accounts.permissions IS 'Role-based permissions array: player, gm (game master), admin';
COMMENT ON COLUMN accounts.banned IS 'Account ban flag for moderation enforcement';

-- +migrate Down

DROP INDEX IF EXISTS idx_accounts_steam;
DROP INDEX IF EXISTS idx_accounts_google;
DROP INDEX IF EXISTS idx_accounts_apple;
DROP INDEX IF EXISTS idx_accounts_device;
DROP INDEX IF EXISTS idx_accounts_email;
DROP TABLE IF EXISTS accounts;
