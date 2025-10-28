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
	"strings"

	"github.com/gofrs/uuid/v5"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

// MMORPGSecurityInterceptor validates MMORPG JWT tokens and enforces authentication.
// Extends Nakama's security interceptor with MMORPG-specific token validation and permissions.
//
// This middleware:
// - Extracts JWT from Authorization header
// - Validates token signature and expiration using ValidateMMORPGToken
// - Populates context with account_id, username, permissions, tokenId
// - Enforces authentication for all RPCs except authentication endpoints
//
// Context population:
// - ctx.accountId (uuid.UUID) - Account UUID for rate limiting and authorization
// - ctx.username (string) - Display name for audit logs
// - ctx.permissions ([]string) - RBAC permissions array (e.g., ["player", "gm"])
// - ctx.tokenId (string) - Token UUID for revocation tracking
// - ctx.expiresAt (int64) - Token expiration timestamp
// - ctx.issuedAt (int64) - Token issued timestamp
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - validateToken method
// Task: 1.2.5 - Implement session token validation
func MMORPGSecurityInterceptor(logger *zap.Logger, config Config, ctx context.Context, req interface{}, fullMethod string) (context.Context, error) {
	switch fullMethod {
	case "/nakama.api.Nakama/Healthcheck":
		// Healthcheck has no security
		return ctx, nil
	case "/nakama.api.Nakama/AuthenticateDeviceMMORPG":
		fallthrough
	case "/nakama.api.Nakama/AuthenticateEmailMMORPG":
		fallthrough
	case "/nakama.api.Nakama/AuthenticateAppleMMORPG":
		fallthrough
	case "/nakama.api.Nakama/AuthenticateGoogleMMORPG":
		fallthrough
	case "/nakama.api.Nakama/AuthenticateSteamMMORPG":
		// Authentication endpoints require server key only
		return validateServerKey(logger, config, ctx)
	default:
		// All other endpoints require MMORPG JWT authentication
		return validateMMORPGToken(logger, config, ctx)
	}
}

// validateServerKey checks for valid server key in authorization header.
// Used for authentication endpoints that don't require user tokens.
func validateServerKey(logger *zap.Logger, config Config, ctx context.Context) (context.Context, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		logger.Error("Cannot extract metadata from incoming context")
		return nil, status.Error(codes.FailedPrecondition, "Cannot extract metadata from incoming context")
	}

	auth, ok := md["authorization"]
	if !ok {
		auth, ok = md["grpcgateway-authorization"]
	}
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "Server key required")
	}
	if len(auth) != 1 {
		return nil, status.Error(codes.Unauthenticated, "Server key required")
	}

	username, _, ok := parseBasicAuth(auth[0])
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "Server key invalid")
	}
	if username != config.GetSocket().ServerKey {
		return nil, status.Error(codes.Unauthenticated, "Server key invalid")
	}

	return ctx, nil
}

// validateMMORPGToken extracts and validates MMORPG JWT token from authorization header.
// Populates context with account information and permissions for downstream handlers.
func validateMMORPGToken(logger *zap.Logger, config Config, ctx context.Context) (context.Context, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		logger.Error("Cannot extract metadata from incoming context")
		return nil, status.Error(codes.FailedPrecondition, "Cannot extract metadata from incoming context")
	}

	auth, ok := md["authorization"]
	if !ok {
		auth, ok = md["grpcgateway-authorization"]
	}
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "Auth token required")
	}
	if len(auth) != 1 {
		return nil, status.Error(codes.Unauthenticated, "Auth token invalid")
	}

	// Parse Bearer token
	accountID, username, permissions, exp, tokenId, issuedAt, ok := parseMMORPGBearerAuth(config.GetSession().EncryptionKey, auth[0])
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "Auth token invalid")
	}

	// Populate context with MMORPG account information
	ctx = populateMMORPGCtx(ctx, accountID, username, permissions, tokenId, exp, issuedAt)

	return ctx, nil
}

// parseMMORPGBearerAuth extracts and validates MMORPG JWT token from Bearer authorization header.
//
// Returns:
//   - accountID: Account UUID for identification
//   - username: Display name for audit logs
//   - permissions: RBAC permissions array (e.g., ["player", "gm"])
//   - exp: Token expiration timestamp
//   - tokenId: Unique token identifier for revocation
//   - issuedAt: Token issued timestamp
//   - ok: true if token is valid and not expired
func parseMMORPGBearerAuth(signingKey string, auth string) (accountID uuid.UUID, username string, permissions []string, exp int64, tokenId string, issuedAt int64, ok bool) {
	if auth == "" {
		return
	}
	const prefix = "Bearer "
	if !strings.HasPrefix(auth, prefix) {
		return
	}

	// Extract token from "Bearer <token>"
	tokenString := auth[len(prefix):]

	// Validate MMORPG JWT token
	claims, err := ValidateMMORPGToken(signingKey, tokenString)
	if err != nil {
		return
	}

	// Parse account ID
	accountID, err = uuid.FromString(claims.AccountId)
	if err != nil {
		return
	}

	return accountID, claims.Username, claims.Permissions, claims.ExpiresAt, claims.TokenId, claims.IssuedAt, true
}

// populateMMORPGCtx adds MMORPG account context to the request context.
// This context is used by downstream handlers for authorization, rate limiting, and audit logging.
//
// Context keys (reuses standard Nakama keys + adds permissions):
//   - ctxUserIDKey: Account UUID (uuid.UUID) - reuses Nakama's user ID key
//   - ctxUsernameKey: Display name (string) - reuses Nakama's username key
//   - ctxPermissionsKey: RBAC permissions array ([]string) - MMORPG-specific
//   - ctxTokenIDKey: Token UUID for revocation (string) - reuses Nakama's token ID key
//   - ctxExpiryKey: Token expiration timestamp (int64) - reuses Nakama's expiry key
//   - ctxTokenIssuedAtKey: Token issued timestamp (int64) - reuses Nakama's issued at key
func populateMMORPGCtx(ctx context.Context, accountID uuid.UUID, username string, permissions []string, tokenId string, exp int64, issuedAt int64) context.Context {
	ctx = context.WithValue(ctx, ctxUserIDKey{}, accountID)          // Reuse Nakama's user ID key (account_id = user_id in MMORPG context)
	ctx = context.WithValue(ctx, ctxUsernameKey{}, username)         // Reuse Nakama's username key
	ctx = context.WithValue(ctx, ctxPermissionsKey{}, permissions)   // MMORPG-specific permissions array
	ctx = context.WithValue(ctx, ctxTokenIDKey{}, tokenId)           // Reuse Nakama's token ID key
	ctx = context.WithValue(ctx, ctxExpiryKey{}, exp)                // Reuse Nakama's expiry key
	ctx = context.WithValue(ctx, ctxTokenIssuedAtKey{}, issuedAt)    // Reuse Nakama's issued at key
	return ctx
}

// Context key types for MMORPG authentication
// Reuse Nakama's standard keys from api.go
// (ctxUserIDKey, ctxUsernameKey, ctxTokenIDKey, ctxExpiryKey, ctxTokenIssuedAtKey)

// MMORPG-specific context key for permissions
type ctxPermissionsKey struct{}

// GetAccountIdFromContext extracts account UUID from request context.
// Returns zero UUID if not present (should never happen after middleware).
// Note: In MMORPG context, account_id maps to Nakama's user_id.
func GetAccountIdFromContext(ctx context.Context) uuid.UUID {
	if val := ctx.Value(ctxUserIDKey{}); val != nil {
		return val.(uuid.UUID)
	}
	return uuid.Nil
}

// GetPermissionsFromContext extracts permissions array from request context.
// Returns empty slice if not present (should never happen after middleware).
func GetPermissionsFromContext(ctx context.Context) []string {
	if val := ctx.Value(ctxPermissionsKey{}); val != nil {
		return val.([]string)
	}
	return []string{}
}

// GetTokenIdFromContext extracts token ID from request context.
// Returns empty string if not present.
func GetTokenIdFromContext(ctx context.Context) string {
	if val := ctx.Value(ctxTokenIDKey{}); val != nil {
		return val.(string)
	}
	return ""
}

// HasPermission checks if the current user has a specific permission.
// Used for RBAC enforcement in handlers.
//
// Example usage:
//
//	if !HasPermission(ctx, "gm") {
//	    return status.Error(codes.PermissionDenied, "GM permission required")
//	}
func HasPermission(ctx context.Context, permission string) bool {
	permissions := GetPermissionsFromContext(ctx)
	for _, p := range permissions {
		if p == permission {
			return true
		}
	}
	return false
}

// RequirePermission enforces permission check and returns error if not authorized.
// Convenience function for handlers that require specific permissions.
//
// Example usage:
//
//	if err := RequirePermission(ctx, "gm"); err != nil {
//	    return err
//	}
func RequirePermission(ctx context.Context, permission string) error {
	if !HasPermission(ctx, permission) {
		return status.Errorf(codes.PermissionDenied, "Permission required: %s", permission)
	}
	return nil
}
