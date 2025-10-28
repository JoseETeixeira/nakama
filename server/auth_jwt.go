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
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gofrs/uuid/v5"
)

// MMORPGTokenClaims represents JWT claims for MMORPG authentication.
// Extends standard session tokens with permissions array for role-based access control.
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - SessionToken interface
type MMORPGTokenClaims struct {
	TokenId     string   `json:"tid,omitempty"`     // Unique token identifier for revocation
	AccountId   string   `json:"aid,omitempty"`     // Account UUID
	Username    string   `json:"usn,omitempty"`     // Display name
	Permissions []string `json:"pms,omitempty"`     // RBAC permissions: ["player", "moderator", "gm", "admin"]
	ExpiresAt   int64    `json:"exp,omitempty"`     // Unix timestamp when token expires
	IssuedAt    int64    `json:"iat,omitempty"`     // Unix timestamp when token was issued
}

// GetExpirationTime implements jwt.Claims interface
func (m *MMORPGTokenClaims) GetExpirationTime() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(m.ExpiresAt, 0)), nil
}

// GetNotBefore implements jwt.Claims interface
func (m *MMORPGTokenClaims) GetNotBefore() (*jwt.NumericDate, error) {
	return nil, nil
}

// GetIssuedAt implements jwt.Claims interface
func (m *MMORPGTokenClaims) GetIssuedAt() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(m.IssuedAt, 0)), nil
}

// GetAudience implements jwt.Claims interface
func (m *MMORPGTokenClaims) GetAudience() (jwt.ClaimStrings, error) {
	return []string{}, nil
}

// GetIssuer implements jwt.Claims interface
func (m *MMORPGTokenClaims) GetIssuer() (string, error) {
	return "", nil
}

// GetSubject implements jwt.Claims interface
func (m *MMORPGTokenClaims) GetSubject() (string, error) {
	return m.AccountId, nil
}

// GenerateMMORPGToken creates a JWT session token for MMORPG authentication.
//
// This function issues JWT tokens with account_id, permissions array, and expiration
// as specified in Requirement 1 (Player Authentication). Tokens are signed using HS256
// and should be transmitted over TLS 1.2+ for security.
//
// Parameters:
//   - signingKey: Secret key for HMAC-SHA256 signing (from config, minimum 32 bytes recommended)
//   - accountId: UUID of the authenticated account
//   - username: Display name for the account
//   - permissions: Array of permission strings for RBAC (e.g., ["player"], ["player", "moderator"])
//   - tokenExpirySec: Time-to-live in seconds (typically 3600-86400)
//
// Returns:
//   - token: Signed JWT string
//   - tokenId: Unique identifier for this token (for revocation tracking)
//   - expiresAt: Unix timestamp when token expires
//
// Example permissions:
//   - ["player"]: Standard player account
//   - ["player", "moderator"]: Player with moderation privileges
//   - ["player", "gm"]: Game master with live-ops capabilities
//   - ["player", "admin"]: Full administrative access
//
// Security considerations:
//   - Tokens MUST be transmitted over TLS 1.2+ only
//   - signingKey should be rotated periodically and stored securely
//   - Expired tokens are automatically rejected by JWT validation
//   - Token revocation requires maintaining a revocation list (tokenId-based)
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - SessionToken interface
func GenerateMMORPGToken(signingKey string, accountId string, username string, permissions []string, tokenExpirySec int64) (token string, tokenId string, expiresAt int64) {
	now := time.Now().UTC()
	tokenId = uuid.Must(uuid.NewV4()).String()
	issuedAt := now.Unix()
	expiresAt = now.Add(time.Duration(tokenExpirySec) * time.Second).Unix()

	claims := &MMORPGTokenClaims{
		TokenId:     tokenId,
		AccountId:   accountId,
		Username:    username,
		Permissions: permissions,
		ExpiresAt:   expiresAt,
		IssuedAt:    issuedAt,
	}

	jwtToken := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signedToken, _ := jwtToken.SignedString([]byte(signingKey))

	return signedToken, tokenId, expiresAt
}

// ValidateMMORPGToken verifies and parses an MMORPG JWT token.
//
// This function validates token signature, expiration, and extracts claims for authorization.
// Used by middleware to authenticate incoming RPC requests and enforce per-account rate limits.
//
// Parameters:
//   - signingKey: Secret key used to sign the token (must match generation key)
//   - tokenString: JWT string from client (typically from Authorization header)
//
// Returns:
//   - claims: Parsed token claims if valid
//   - error: Non-nil if token is invalid, expired, or malformed
//
// Validation checks:
//   - Signature verification (prevents tampering)
//   - Expiration time (rejects expired tokens)
//   - Signing method (only HS256 accepted)
//   - Claims structure (must be MMORPGTokenClaims)
//
// Usage in middleware:
//
//	claims, err := ValidateMMORPGToken(config.SigningKey, authHeader)
//	if err != nil {
//	    return status.Error(codes.Unauthenticated, "Invalid session token")
//	}
//	// Enforce rate limit based on claims.AccountId
//	// Check permissions: if !contains(claims.Permissions, "gm") { return error }
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - validateToken method
func ValidateMMORPGToken(signingKey string, tokenString string) (*MMORPGTokenClaims, error) {
	claims := &MMORPGTokenClaims{}

	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		return []byte(signingKey), nil
	}, jwt.WithExpirationRequired(), jwt.WithValidMethods([]string{"HS256"}))

	if err != nil {
		return nil, err
	}

	if !token.Valid {
		return nil, jwt.ErrTokenInvalidClaims
	}

	return claims, nil
}

// RefreshMMORPGToken generates a new JWT token using a refresh token flow.
//
// This function allows clients to obtain a new access token without re-authenticating,
// improving user experience for long-lived sessions. The refresh token itself should
// have a longer expiry (e.g., 7-30 days) than access tokens (e.g., 1-24 hours).
//
// Parameters:
//   - signingKey: Secret key for signing the new token
//   - oldClaims: Claims from the validated refresh token (permissions, accountId, username preserved)
//   - tokenExpirySec: TTL for the new access token
//
// Returns:
//   - token: New signed JWT string
//   - tokenId: New unique identifier
//   - expiresAt: New expiration timestamp
//
// Security considerations:
//   - Refresh tokens should use a different signing key than access tokens
//   - Refresh tokens should be single-use (revoke after successful refresh)
//   - Refresh operations should be rate-limited to prevent abuse
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - refreshToken method
func RefreshMMORPGToken(signingKey string, oldClaims *MMORPGTokenClaims, tokenExpirySec int64) (token string, tokenId string, expiresAt int64) {
	// Generate new token with same account context but fresh expiry and tokenId
	return GenerateMMORPGToken(signingKey, oldClaims.AccountId, oldClaims.Username, oldClaims.Permissions, tokenExpirySec)
}
