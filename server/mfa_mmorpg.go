// Copyright 2025 Heroic Labs
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package server

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"strings"

	"github.com/dgryski/dgoogauth"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// GetAccountMFAData retrieves MFA configuration for an MMORPG account
func GetAccountMFAData(ctx context.Context, db *sql.DB, accountID string) (mfaRequired bool, mfaSecret, mfaRecoveryCodes []byte, err error) {
	query := "SELECT mfa_required, mfa_secret, mfa_recovery_codes FROM accounts WHERE account_id = $1"
	err = db.QueryRowContext(ctx, query, accountID).Scan(&mfaRequired, &mfaSecret, &mfaRecoveryCodes)
	return
}

// ValidateAccountMFACode validates a TOTP code or recovery code for an MMORPG account
func ValidateAccountMFACode(ctx context.Context, logger *zap.Logger, db *sql.DB, config Config, accountID, mfaCode string, mfaSecret, mfaRecoveryCodes []byte) error {
	if strings.TrimSpace(mfaCode) == "" {
		return status.Error(codes.PermissionDenied, "A MFA code is required.")
	}

	// Decrypt MFA secret
	decryptedSecret, err := decrypt(mfaSecret, []byte(config.GetMFA().StorageEncryptionKey))
	if err != nil {
		logger.Error("Failed to decrypt MFA secret.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to decrypt MFA secret.")
	}

	// Decrypt recovery codes
	recoveryCodesStr, err := decrypt(mfaRecoveryCodes, []byte(config.GetMFA().StorageEncryptionKey))
	if err != nil {
		logger.Error("Failed to decrypt MFA recovery codes.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to decrypt MFA recovery codes.")
	}

	recoveryCodesStrArr := strings.Split(string(recoveryCodesStr), ",")
	recoveryCodes := make([]int, len(recoveryCodesStrArr))
	for i, codeStr := range recoveryCodesStrArr {
		recoveryCodes[i], err = strconv.Atoi(codeStr)
		if err != nil {
			logger.Error("Failed to parse MFA recovery code as integer.", zap.Error(err), zap.String("accountID", accountID))
			return status.Error(codes.Internal, "Failed to parse MFA recovery codes.")
		}
	}

	// Create OTP config
	optConfig := &dgoogauth.OTPConfig{
		Secret:       string(decryptedSecret),
		WindowSize:   MFAWindowSize,
		UTC:          true,
		ScratchCodes: recoveryCodes,
	}

	// Authenticate the code
	ok, err := optConfig.Authenticate(mfaCode)
	if err != nil {
		return status.Error(codes.InvalidArgument, "The MFA code used is incorrectly formatted.")
	}
	if !ok {
		return status.Error(codes.Unauthenticated, "The MFA code is invalid.")
	}

	// If a recovery code was used, update the database
	if len(optConfig.ScratchCodes) != len(recoveryCodesStrArr) {
		recoveryCodesStrArray := make([]string, len(optConfig.ScratchCodes))
		for i, code := range optConfig.ScratchCodes {
			recoveryCodesStrArray[i] = strconv.Itoa(code)
		}

		updatedRecoveryCodes, err := encrypt([]byte(strings.Join(recoveryCodesStrArray, ",")), []byte(config.GetMFA().StorageEncryptionKey))
		if err != nil {
			logger.Error("Failed to encrypt updated MFA recovery codes.", zap.Error(err), zap.String("accountID", accountID))
			return status.Error(codes.Internal, "Failed to encrypt updated MFA recovery codes.")
		}

		if _, err = db.ExecContext(ctx, `UPDATE accounts SET mfa_recovery_codes = $1 WHERE account_id = $2`, updatedRecoveryCodes, accountID); err != nil {
			if errors.Is(err, context.Canceled) {
				return err
			}
			logger.Error("Failed to update MFA recovery codes.", zap.Error(err), zap.String("accountID", accountID))
			return status.Error(codes.Internal, "Failed to update MFA recovery codes.")
		}
	}

	return nil
}

// SetupAccountMFA initializes MFA for an MMORPG account
func SetupAccountMFA(ctx context.Context, logger *zap.Logger, db *sql.DB, config Config, accountID, mfaCode string) error {
	// Generate MFA secret
	mfaSecret, err := generateMFASecret()
	if err != nil {
		logger.Error("Failed to generate MFA secret.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to generate MFA secret.")
	}

	// Generate recovery codes
	recoveryCodes, err := generateRecoveryCodes()
	if err != nil {
		logger.Error("Failed to generate recovery codes.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to generate recovery codes.")
	}

	// Validate the provided TOTP code against the new secret
	optConfig := &dgoogauth.OTPConfig{
		Secret:     mfaSecret,
		WindowSize: MFAWindowSize,
		UTC:        true,
	}

	ok, err := optConfig.Authenticate(mfaCode)
	if err != nil {
		return status.Error(codes.InvalidArgument, "The MFA code used is incorrectly formatted.")
	}
	if !ok {
		return status.Error(codes.Unauthenticated, "The MFA code is invalid. Please verify your authenticator app is set up correctly.")
	}

	// Encrypt secret and recovery codes
	encryptedSecret, err := encrypt([]byte(mfaSecret), []byte(config.GetMFA().StorageEncryptionKey))
	if err != nil {
		logger.Error("Failed to encrypt MFA secret.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to encrypt MFA secret.")
	}

	encryptedRecoveryCodes, err := encrypt([]byte(strings.Join(recoveryCodes, ",")), []byte(config.GetMFA().StorageEncryptionKey))
	if err != nil {
		logger.Error("Failed to encrypt recovery codes.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to encrypt recovery codes.")
	}

	// Update accounts table with MFA data
	query := `UPDATE accounts SET mfa_secret = $1, mfa_recovery_codes = $2 WHERE account_id = $3`
	if _, err = db.ExecContext(ctx, query, encryptedSecret, encryptedRecoveryCodes, accountID); err != nil {
		logger.Error("Failed to save MFA configuration.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to save MFA configuration.")
	}

	return nil
}

// DisableAccountMFA removes MFA from an MMORPG account
func DisableAccountMFA(ctx context.Context, logger *zap.Logger, db *sql.DB, accountID string) error {
	query := `UPDATE accounts SET mfa_secret = NULL, mfa_recovery_codes = NULL, mfa_required = FALSE WHERE account_id = $1`
	if _, err := db.ExecContext(ctx, query, accountID); err != nil {
		logger.Error("Failed to disable MFA.", zap.Error(err), zap.String("accountID", accountID))
		return status.Error(codes.Internal, "Failed to disable MFA.")
	}
	return nil
}

// RequireAccountMFA sets whether MFA is required for an MMORPG account
func RequireAccountMFA(ctx context.Context, logger *zap.Logger, db *sql.DB, accountID string, required bool) error {
	query := `UPDATE accounts SET mfa_required = $1 WHERE account_id = $2`
	if _, err := db.ExecContext(ctx, query, required, accountID); err != nil {
		logger.Error("Failed to update MFA requirement.", zap.Error(err), zap.String("accountID", accountID), zap.Bool("required", required))
		return status.Error(codes.Internal, "Failed to update MFA requirement.")
	}
	return nil
}
