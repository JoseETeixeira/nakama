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
	"encoding/json"
	"time"

	"github.com/gofrs/uuid/v5"
	"github.com/golang-jwt/jwt/v5"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// MFASetupTokenClaims represents the JWT claims for MFA setup tokens
type MFASetupTokenClaims struct {
	TokenID     string `json:"tid,omitempty"`
	AccountID   string `json:"account_id,omitempty"`
	ExpiryTime  int64  `json:"exp,omitempty"`
	CreateTime  int64  `json:"crt,omitempty"`
	MFASecret   string `json:"secret,omitempty"`
	MFAUrl      string `json:"mfa_url,omitempty"`
	MFARequired bool   `json:"mfa_required,omitempty"`
}

func (s *MFASetupTokenClaims) GetExpirationTime() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(s.ExpiryTime, 0)), nil
}
func (s *MFASetupTokenClaims) GetNotBefore() (*jwt.NumericDate, error) {
	return nil, nil
}
func (s *MFASetupTokenClaims) GetIssuedAt() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(s.CreateTime, 0)), nil
}
func (s *MFASetupTokenClaims) GetAudience() (jwt.ClaimStrings, error) {
	return []string{}, nil
}
func (s *MFASetupTokenClaims) GetIssuer() (string, error) {
	return "", nil
}
func (s *MFASetupTokenClaims) GetSubject() (string, error) {
	return "", nil
}

// RpcInitializeMFA initializes MFA setup for an account and returns setup token with QR code URL
// This is intended to be registered as an RPC function in the runtime
func RpcInitializeMFA(ctx context.Context, logger *zap.Logger, db *sql.DB, config Config, payload string) (string, error) {
	accountID, ok := ctx.Value(ctxUserIDKey{}).(uuid.UUID)
	if !ok || accountID == uuid.Nil {
		return "", status.Error(codes.Unauthenticated, "Invalid session.")
	}

	username, ok := ctx.Value(ctxUsernameKey{}).(string)
	if !ok || username == "" {
		username = accountID.String()
	}

	// Check if MFA is already enabled
	mfaRequired, mfaSecret, _, err := GetAccountMFAData(ctx, db, accountID.String())
	if err != nil && err != sql.ErrNoRows {
		logger.Error("Failed to retrieve MFA data", zap.Error(err), zap.String("accountID", accountID.String()))
		return "", status.Error(codes.Internal, "Failed to retrieve MFA data.")
	}

	if mfaSecret != nil && len(mfaSecret) > 0 {
		return "", status.Error(codes.AlreadyExists, "MFA is already enabled for this account.")
	}

	// Generate new MFA secret
	mfaSecretStr, err := generateMFASecret()
	if err != nil {
		logger.Error("Failed to generate MFA secret", zap.Error(err), zap.String("accountID", accountID.String()))
		return "", status.Error(codes.Internal, "Failed to generate MFA secret.")
	}

	// Generate QR code URL
	mfaUrl := generateMFAUrl(mfaSecretStr, username)

	// Generate a temporary setup token containing the secret (expires in 10 minutes)
	tokenTime := time.Now()
	tokenExpiry := tokenTime.Add(10 * time.Minute).Unix()

	setupToken, err := generateJWTToken(
		config.GetSession().EncryptionKey,
		&MFASetupTokenClaims{
			TokenID:     uuid.Must(uuid.NewV4()).String(),
			AccountID:   accountID.String(),
			ExpiryTime:  tokenExpiry,
			CreateTime:  tokenTime.Unix(),
			MFASecret:   mfaSecretStr,
			MFAUrl:      mfaUrl,
			MFARequired: mfaRequired,
		},
	)
	if err != nil {
		logger.Error("Failed to generate MFA setup token", zap.Error(err), zap.String("accountID", accountID.String()))
		return "", status.Error(codes.Internal, "Failed to generate MFA setup token.")
	}

	response := map[string]interface{}{
		"setup_token": setupToken,
		"qr_code_url": mfaUrl,
		"secret":      mfaSecretStr,
	}

	responseBytes, _ := json.Marshal(response)
	return string(responseBytes), nil
}

// RpcCompleteMFASetup completes MFA setup by validating a TOTP code
func RpcCompleteMFASetup(ctx context.Context, logger *zap.Logger, db *sql.DB, config Config, payload string) (string, error) {
	accountID, ok := ctx.Value(ctxUserIDKey{}).(uuid.UUID)
	if !ok || accountID == uuid.Nil {
		return "", status.Error(codes.Unauthenticated, "Invalid session.")
	}

	// Payload should be JSON: {"setup_token": "...", "totp_code": "123456"}
	var input struct {
		SetupToken string `json:"setup_token"`
		TotpCode   string `json:"totp_code"`
	}

	if err := json.Unmarshal([]byte(payload), &input); err != nil {
		return "", status.Error(codes.InvalidArgument, "Invalid payload format.")
	}

	if input.SetupToken == "" || input.TotpCode == "" {
		return "", status.Error(codes.InvalidArgument, "setup_token and totp_code are required.")
	}

	// Parse and validate the setup token
	token, err := jwt.ParseWithClaims(input.SetupToken, &MFASetupTokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(config.GetSession().EncryptionKey), nil
	}, jwt.WithExpirationRequired(), jwt.WithValidMethods([]string{"HS256"}))

	if err != nil || !token.Valid {
		return "", status.Error(codes.InvalidArgument, "Invalid or expired setup token.")
	}

	claims, ok := token.Claims.(*MFASetupTokenClaims)
	if !ok || claims.AccountID != accountID.String() {
		return "", status.Error(codes.InvalidArgument, "Setup token does not match account.")
	}

	// Setup MFA with the provided code
	if err := SetupAccountMFA(ctx, logger, db, config, accountID.String(), input.TotpCode); err != nil {
		return "", err
	}

	return `{"success": true, "message": "MFA has been successfully enabled for your account."}`, nil
}

// RpcDisableMFA disables MFA for an account (requires current TOTP code)
func RpcDisableMFA(ctx context.Context, logger *zap.Logger, db *sql.DB, config Config, payload string) (string, error) {
	accountID, ok := ctx.Value(ctxUserIDKey{}).(uuid.UUID)
	if !ok || accountID == uuid.Nil {
		return "", status.Error(codes.Unauthenticated, "Invalid session.")
	}

	// Payload should be JSON: {"totp_code": "123456"}
	var input struct {
		TotpCode string `json:"totp_code"`
	}

	if err := json.Unmarshal([]byte(payload), &input); err != nil {
		return "", status.Error(codes.InvalidArgument, "Invalid payload format.")
	}

	if input.TotpCode == "" {
		return "", status.Error(codes.InvalidArgument, "totp_code is required.")
	}

	// Get current MFA data
	mfaRequired, mfaSecret, mfaRecoveryCodes, err := GetAccountMFAData(ctx, db, accountID.String())
	if err != nil {
		if err == sql.ErrNoRows {
			return "", status.Error(codes.NotFound, "MFA is not enabled for this account.")
		}
		logger.Error("Failed to retrieve MFA data", zap.Error(err), zap.String("accountID", accountID.String()))
		return "", status.Error(codes.Internal, "Failed to retrieve MFA data.")
	}

	if mfaSecret == nil || len(mfaSecret) == 0 {
		return "", status.Error(codes.NotFound, "MFA is not enabled for this account.")
	}

	// Validate the TOTP code before disabling
	if err := ValidateAccountMFACode(ctx, logger, db, config, accountID.String(), input.TotpCode, mfaSecret, mfaRecoveryCodes); err != nil {
		return "", err
	}

	// Disable MFA
	if err := DisableAccountMFA(ctx, logger, db, accountID.String()); err != nil {
		return "", err
	}

	return `{"success": true, "message": "MFA has been disabled for your account."}`, nil
}

// RpcRequireMFA sets whether MFA is required for an account
func RpcRequireMFA(ctx context.Context, logger *zap.Logger, db *sql.DB, config Config, payload string) (string, error) {
	accountID, ok := ctx.Value(ctxUserIDKey{}).(uuid.UUID)
	if !ok || accountID == uuid.Nil {
		return "", status.Error(codes.Unauthenticated, "Invalid session.")
	}

	// Payload should be JSON: {"required": true}
	var input struct {
		Required bool `json:"required"`
	}

	if err := json.Unmarshal([]byte(payload), &input); err != nil {
		return "", status.Error(codes.InvalidArgument, "Invalid payload format.")
	}

	// Check if MFA is enabled before allowing it to be required
	if input.Required {
		_, mfaSecret, _, err := GetAccountMFAData(ctx, db, accountID.String())
		if err != nil {
			logger.Error("Failed to retrieve MFA data", zap.Error(err), zap.String("accountID", accountID.String()))
			return "", status.Error(codes.Internal, "Failed to retrieve MFA data.")
		}

		if mfaSecret == nil || len(mfaSecret) == 0 {
			return "", status.Error(codes.FailedPrecondition, "MFA must be enabled before it can be required.")
		}
	}

	// Update MFA requirement
	if err := RequireAccountMFA(ctx, logger, db, accountID.String(), input.Required); err != nil {
		return "", err
	}

	return `{"success": true, "message": "MFA requirement has been updated."}`, nil
}
