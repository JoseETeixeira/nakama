/*
 * Copyright 2025 Heroic Labs
 * MMORPG Feature Set - Accounts MFA Migration
 *
 * Adds Multi-Factor Authentication (MFA) support to accounts table.
 * Implements TOTP-based two-factor authentication that can be enabled
 * per account for enhanced security.
 *
 * Requirements: Requirement 1 (Player Authentication)
 * Design Reference: Authentication Service - Optional 2FA for new devices
 * Task: 1.2.7 - Add optional 2FA support
 */

-- +migrate Up

-- Add MFA columns to accounts table
ALTER TABLE accounts
    ADD COLUMN mfa_secret BYTEA DEFAULT NULL,
    ADD COLUMN mfa_recovery_codes BYTEA DEFAULT NULL,
    ADD COLUMN mfa_required BOOLEAN DEFAULT FALSE;

-- Table comments for MFA columns
COMMENT ON COLUMN accounts.mfa_secret IS 'Encrypted TOTP secret for two-factor authentication (NULL if 2FA disabled)';
COMMENT ON COLUMN accounts.mfa_recovery_codes IS 'Encrypted backup recovery codes for account access if TOTP unavailable';
COMMENT ON COLUMN accounts.mfa_required IS 'Whether MFA is required for this account (enforced on all logins)';

-- +migrate Down

ALTER TABLE accounts
    DROP COLUMN mfa_secret,
    DROP COLUMN mfa_recovery_codes,
    DROP COLUMN mfa_required;
