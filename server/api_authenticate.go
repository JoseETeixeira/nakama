// Copyright 2018 The Nakama Authors
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
	"math/rand"
	"regexp"
	"strings"
	"time"

	"github.com/gofrs/uuid/v5"
	"github.com/golang-jwt/jwt/v5"
	"github.com/heroiclabs/nakama-common/api"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var (
	invalidUsernameRegex = regexp.MustCompilePOSIX("([[:cntrl:]]|[[\t\n\r\f\v]])+")
	invalidCharsRegex    = regexp.MustCompilePOSIX("([[:cntrl:]]|[[:space:]])+")
	emailRegex           = regexp.MustCompile(`^.+@.+\..+$`)
)

type SessionTokenClaims struct {
	TokenId   string            `json:"tid,omitempty"`
	UserId    string            `json:"uid,omitempty"`
	Username  string            `json:"usn,omitempty"`
	Vars      map[string]string `json:"vrs,omitempty"`
	ExpiresAt int64             `json:"exp,omitempty"`
	IssuedAt  int64             `json:"iat,omitempty"`
}

func (s *SessionTokenClaims) GetExpirationTime() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(s.ExpiresAt, 0)), nil
}
func (s *SessionTokenClaims) GetNotBefore() (*jwt.NumericDate, error) {
	return nil, nil
}
func (s *SessionTokenClaims) GetIssuedAt() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(s.IssuedAt, 0)), nil
}
func (s *SessionTokenClaims) GetAudience() (jwt.ClaimStrings, error) {
	return []string{}, nil
}
func (s *SessionTokenClaims) GetIssuer() (string, error) {
	return "", nil
}
func (s *SessionTokenClaims) GetSubject() (string, error) {
	return "", nil
}

func (s *ApiServer) AuthenticateApple(ctx context.Context, in *api.AuthenticateAppleRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateApple(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if s.config.GetSocial().Apple.BundleId == "" {
		return nil, status.Error(codes.FailedPrecondition, "Apple authentication is not configured.")
	}

	if in.Account == nil || in.Account.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "Apple ID token is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, created, err := AuthenticateApple(ctx, s.logger, s.db, s.socialClient, s.config.GetSocial().Apple.BundleId, in.Account.Token, username, create)
	if err != nil {
		return nil, err
	}

	uid := uuid.Must(uuid.FromString(dbUserID))
	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uid)
	}

	tokenIssuedAt := time.Now().Unix()
	tokenID := uuid.Must(uuid.NewV4()).String()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateApple(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateCustom(ctx context.Context, in *api.AuthenticateCustomRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateCustom(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if in.Account == nil || in.Account.Id == "" {
		return nil, status.Error(codes.InvalidArgument, "Custom ID is required.")
	} else if invalidCharsRegex.MatchString(in.Account.Id) {
		return nil, status.Error(codes.InvalidArgument, "Custom ID invalid, no spaces or control characters allowed.")
	} else if len(in.Account.Id) < 6 || len(in.Account.Id) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Custom ID invalid, must be 6-128 bytes.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, created, err := AuthenticateCustom(ctx, s.logger, s.db, in.Account.Id, username, create)
	if err != nil {
		return nil, err
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateCustom(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateDevice(ctx context.Context, in *api.AuthenticateDeviceRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateDevice(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if in.Account == nil || in.Account.Id == "" {
		return nil, status.Error(codes.InvalidArgument, "Device ID is required.")
	} else if invalidCharsRegex.MatchString(in.Account.Id) {
		return nil, status.Error(codes.InvalidArgument, "Device ID invalid, no spaces or control characters allowed.")
	} else if len(in.Account.Id) < 10 || len(in.Account.Id) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Device ID invalid, must be 10-128 bytes.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, created, err := AuthenticateDevice(ctx, s.logger, s.db, in.Account.Id, username, create)
	if err != nil {
		return nil, err
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateDevice(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

// AuthenticateDeviceMMORPG handles MMORPG-specific device authentication with permissions.
// Returns SessionToken containing account_id, username, and permissions array.
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - device ID authentication with auto-registration
// Task: 1.2.2 - Implement device authentication
func (s *ApiServer) AuthenticateDeviceMMORPG(ctx context.Context, in *api.AuthenticateDeviceRequest) (*api.Session, error) {
	// Extract client IP for rate limiting
	ip, _ := extractClientAddressFromContext(s.logger, ctx)

	// Check rate limiting - use device ID as identifier
	deviceID := ""
	if in.Account != nil {
		deviceID = in.Account.Id
	}
	if !s.loginAttemptCache.Allow(deviceID, ip) {
		return nil, status.Error(codes.ResourceExhausted, "Try again later.")
	}

	// Before hook (reuse standard device auth before hook)
	if fn := s.runtime.BeforeAuthenticateDevice(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	// Validate device ID
	if in.Account == nil || in.Account.Id == "" {
		return nil, status.Error(codes.InvalidArgument, "Device ID is required.")
	} else if invalidCharsRegex.MatchString(in.Account.Id) {
		return nil, status.Error(codes.InvalidArgument, "Device ID invalid, no spaces or control characters allowed.")
	} else if len(in.Account.Id) < 10 || len(in.Account.Id) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Device ID invalid, must be 10-128 bytes.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	// Authenticate using MMORPG accounts table
	accountID, dbUsername, permissions, created, err := AuthenticateDeviceMMORPG(ctx, s.logger, s.db, in.Account.Id, username, create)
	if err != nil {
		// Add failed attempt on authentication error
		if lockout, until := s.loginAttemptCache.Add(deviceID, ip); lockout != LockoutTypeNone {
			s.logger.Warn("MMORPG device authentication lockout triggered", zap.String("device_id", deviceID), zap.String("ip", ip), zap.Time("locked_until", until))
		}
		return nil, err
	}

	// Reset attempts on successful authentication
	s.loginAttemptCache.Reset(deviceID)

	// Generate MMORPG JWT token with permissions
	tokenExpirySec := s.config.GetSession().TokenExpirySec
	token, tokenID, expiresAt := GenerateMMORPGToken(
		s.config.GetSession().EncryptionKey,
		accountID,
		dbUsername,
		permissions,
		tokenExpirySec,
	)

	// Note: MMORPG tokens don't use refresh tokens in this implementation
	// SessionCache is not used for MMORPG tokens - stateless JWT validation only
	session := &api.Session{
		Created: created,
		Token:   token,
	}

	// After hook (reuse standard device auth after hook)
	if fn := s.runtime.AfterAuthenticateDevice(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(accountID))
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, expiresAt, time.Now().Unix())
			return fn(ctx, s.logger, accountID, dbUsername, in.Account.Vars, expiresAt, clientIP, clientPort, session, in)
		}

		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateEmail(ctx context.Context, in *api.AuthenticateEmailRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateEmail(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	email := in.Account
	if email == nil {
		return nil, status.Error(codes.InvalidArgument, "Email address and password is required.")
	}

	var attemptUsernameLogin bool
	if email.Email == "" {
		// Password was supplied, but no email. Perhaps the user is attempting to login with username/password.
		attemptUsernameLogin = true
	} else if invalidCharsRegex.MatchString(email.Email) {
		return nil, status.Error(codes.InvalidArgument, "Invalid email address, no spaces or control characters allowed.")
	} else if !emailRegex.MatchString(email.Email) {
		return nil, status.Error(codes.InvalidArgument, "Invalid email address format.")
	} else if len(email.Email) < 10 || len(email.Email) > 255 {
		return nil, status.Error(codes.InvalidArgument, "Invalid email address, must be 10-255 bytes.")
	}

	if len(email.Password) < 8 {
		return nil, status.Error(codes.InvalidArgument, "Password must be at least 8 characters long.")
	}

	username := in.Username
	if username == "" {
		// If no username was supplied and the email was missing.
		if attemptUsernameLogin {
			return nil, status.Error(codes.InvalidArgument, "Username is required when email address is not supplied.")
		}

		// Email address was supplied, we are allowed to generate a username.
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	var dbUserID string
	var created bool
	var err error

	if attemptUsernameLogin {
		// Attempting to log in with username/password. Create flag is ignored, creation is not possible here.
		dbUserID, err = AuthenticateUsername(ctx, s.logger, s.db, username, email.Password)
	} else {
		// Attempting email authentication, may or may not create.
		cleanEmail := strings.ToLower(email.Email)
		create := in.Create == nil || in.Create.Value

		dbUserID, username, created, err = AuthenticateEmail(ctx, s.logger, s.db, cleanEmail, email.Password, username, create)
	}
	if err != nil {
		return nil, err
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, username, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, username, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateEmail(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, username, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, username, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

// AuthenticateEmailMMORPG handles MMORPG-specific email + password authentication with permissions.
// Returns SessionToken containing account_id, username, and permissions array.
// Passwords are hashed using bcrypt for secure storage.
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - email authentication with bcrypt hashing
// Task: 1.2.3 - Implement email authentication
func (s *ApiServer) AuthenticateEmailMMORPG(ctx context.Context, in *api.AuthenticateEmailRequest) (*api.Session, error) {
	// Extract client IP for rate limiting
	ip, _ := extractClientAddressFromContext(s.logger, ctx)

	// Check rate limiting - use email as identifier (will be empty if validation fails, but that's OK)
	email := ""
	if in.Account != nil {
		email = in.Account.Email
	}
	if !s.loginAttemptCache.Allow(email, ip) {
		return nil, status.Error(codes.ResourceExhausted, "Try again later.")
	}

	// Before hook (reuse standard email auth before hook)
	if fn := s.runtime.BeforeAuthenticateEmail(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	// Validate email and password
	if in.Account == nil {
		return nil, status.Error(codes.InvalidArgument, "Email address and password is required.")
	}

	email = in.Account.Email
	if email == "" {
		return nil, status.Error(codes.InvalidArgument, "Email address is required.")
	} else if !emailRegex.MatchString(email) {
		return nil, status.Error(codes.InvalidArgument, "Invalid email address format.")
	} else if len(email) < 3 || len(email) > 255 {
		return nil, status.Error(codes.InvalidArgument, "Email address must be 3-255 bytes.")
	}

	password := in.Account.Password
	if password == "" {
		return nil, status.Error(codes.InvalidArgument, "Password is required.")
	} else if len(password) < 8 {
		return nil, status.Error(codes.InvalidArgument, "Password must be at least 8 characters.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	// Authenticate using MMORPG accounts table
	accountID, dbUsername, permissions, created, err := AuthenticateEmailMMORPG(ctx, s.logger, s.db, email, password, username, create)
	if err != nil {
		// Add failed attempt on authentication error
		if lockout, until := s.loginAttemptCache.Add(email, ip); lockout != LockoutTypeNone {
			s.logger.Warn("MMORPG email authentication lockout triggered", zap.String("email", email), zap.String("ip", ip), zap.Time("locked_until", until))
		}
		return nil, err
	}

	// Check for MFA requirement
	_, mfaSecret, mfaRecoveryCodes, err := GetAccountMFAData(ctx, s.db, accountID)
	if err != nil && err != sql.ErrNoRows {
		s.logger.Error("Failed to retrieve MFA data", zap.Error(err), zap.String("accountID", accountID))
		return nil, status.Error(codes.Internal, "Failed to retrieve MFA data.")
	}

	mfaEnabled := mfaSecret != nil && len(mfaSecret) > 0

	if mfaEnabled {
		// MFA is enabled - validate the provided code
		mfaCode := ""
		if in.Account != nil && in.Account.Vars != nil {
			mfaCode = in.Account.Vars["mfa"]
		}

		if err := ValidateAccountMFACode(ctx, s.logger, s.db, s.config, accountID, mfaCode, mfaSecret, mfaRecoveryCodes); err != nil {
			// Add failed attempt on MFA validation error
			if lockout, until := s.loginAttemptCache.Add(email, ip); lockout != LockoutTypeNone {
				s.logger.Warn("MMORPG MFA validation lockout triggered", zap.String("email", email), zap.String("ip", ip), zap.Time("locked_until", until))
			}
			return nil, err
		}
	}

	// Reset attempts on successful authentication
	s.loginAttemptCache.Reset(email)

	// Generate MMORPG JWT token with permissions
	tokenExpirySec := s.config.GetSession().TokenExpirySec
	token, tokenID, expiresAt := GenerateMMORPGToken(
		s.config.GetSession().EncryptionKey,
		accountID,
		dbUsername,
		permissions,
		tokenExpirySec,
	)

	// Note: MMORPG tokens don't use refresh tokens in this implementation
	// SessionCache is not used for MMORPG tokens - stateless JWT validation only
	session := &api.Session{
		Created: created,
		Token:   token,
	}

	// After hook (reuse standard email auth after hook)
	if fn := s.runtime.AfterAuthenticateEmail(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(accountID))
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, expiresAt, time.Now().Unix())
			return fn(ctx, s.logger, accountID, dbUsername, in.Account.Vars, expiresAt, clientIP, clientPort, session, in)
		}

		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

// AuthenticateAppleMMORPG handles MMORPG-specific Apple Sign In authentication with permissions.
// Validates Apple ID token and returns SessionToken with account_id, username, and permissions array.
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - platform token authentication
// Task: 1.2.4 - Implement platform token authentication
func (s *ApiServer) AuthenticateAppleMMORPG(ctx context.Context, in *api.AuthenticateAppleRequest) (*api.Session, error) {
	// Extract client IP for rate limiting
	ip, _ := extractClientAddressFromContext(s.logger, ctx)

	// Check rate limiting - use "apple" as identifier since we don't have apple_id yet
	identifier := "apple:" + ip
	if !s.loginAttemptCache.Allow(identifier, ip) {
		return nil, status.Error(codes.ResourceExhausted, "Try again later.")
	}

	// Before hook (reuse standard Apple auth before hook)
	if fn := s.runtime.BeforeAuthenticateApple(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	// Check if Apple authentication is configured
	if s.config.GetSocial().Apple.BundleId == "" {
		return nil, status.Error(codes.FailedPrecondition, "Apple authentication is not configured.")
	}

	// Validate Apple ID token
	if in.Account == nil || in.Account.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "Apple ID token is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	// Authenticate using MMORPG accounts table
	accountID, dbUsername, permissions, created, err := AuthenticateAppleMMORPG(ctx, s.logger, s.db, s.socialClient, s.config.GetSocial().Apple.BundleId, in.Account.Token, username, create)
	if err != nil {
		// Add failed attempt on authentication error
		if lockout, until := s.loginAttemptCache.Add(identifier, ip); lockout != LockoutTypeNone {
			s.logger.Warn("MMORPG Apple authentication lockout triggered", zap.String("ip", ip), zap.Time("locked_until", until))
		}
		return nil, err
	}

	// Reset attempts on successful authentication
	s.loginAttemptCache.Reset(identifier)

	// Generate MMORPG JWT token with permissions
	tokenExpirySec := s.config.GetSession().TokenExpirySec
	token, tokenID, expiresAt := GenerateMMORPGToken(
		s.config.GetSession().EncryptionKey,
		accountID,
		dbUsername,
		permissions,
		tokenExpirySec,
	)

	session := &api.Session{
		Created: created,
		Token:   token,
	}

	// After hook (reuse standard Apple auth after hook)
	if fn := s.runtime.AfterAuthenticateApple(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(accountID))
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, expiresAt, time.Now().Unix())
			return fn(ctx, s.logger, accountID, dbUsername, in.Account.Vars, expiresAt, clientIP, clientPort, session, in)
		}

		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

// AuthenticateGoogleMMORPG handles MMORPG-specific Google Play Games authentication with permissions.
// Validates Google ID token and returns SessionToken with account_id, username, and permissions array.
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - platform token authentication
// Task: 1.2.4 - Implement platform token authentication
func (s *ApiServer) AuthenticateGoogleMMORPG(ctx context.Context, in *api.AuthenticateGoogleRequest) (*api.Session, error) {
	// Extract client IP for rate limiting
	ip, _ := extractClientAddressFromContext(s.logger, ctx)

	// Check rate limiting - use "google" as identifier since we don't have google_id yet
	identifier := "google:" + ip
	if !s.loginAttemptCache.Allow(identifier, ip) {
		return nil, status.Error(codes.ResourceExhausted, "Try again later.")
	}

	// Before hook (reuse standard Google auth before hook)
	if fn := s.runtime.BeforeAuthenticateGoogle(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	// Validate Google ID token
	if in.Account == nil || in.Account.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "Google access token is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	// Authenticate using MMORPG accounts table
	accountID, dbUsername, permissions, created, err := AuthenticateGoogleMMORPG(ctx, s.logger, s.db, s.socialClient, in.Account.Token, username, create)
	if err != nil {
		// Add failed attempt on authentication error
		if lockout, until := s.loginAttemptCache.Add(identifier, ip); lockout != LockoutTypeNone {
			s.logger.Warn("MMORPG Google authentication lockout triggered", zap.String("ip", ip), zap.Time("locked_until", until))
		}
		return nil, err
	}

	// Reset attempts on successful authentication
	s.loginAttemptCache.Reset(identifier)

	// Generate MMORPG JWT token with permissions
	tokenExpirySec := s.config.GetSession().TokenExpirySec
	token, tokenID, expiresAt := GenerateMMORPGToken(
		s.config.GetSession().EncryptionKey,
		accountID,
		dbUsername,
		permissions,
		tokenExpirySec,
	)

	session := &api.Session{
		Created: created,
		Token:   token,
	}

	// After hook (reuse standard Google auth after hook)
	if fn := s.runtime.AfterAuthenticateGoogle(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(accountID))
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, expiresAt, time.Now().Unix())
			return fn(ctx, s.logger, accountID, dbUsername, in.Account.Vars, expiresAt, clientIP, clientPort, session, in)
		}

		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

// AuthenticateSteamMMORPG handles MMORPG-specific Steam authentication with permissions.
// Validates Steam session ticket and returns SessionToken with account_id, username, and permissions array.
//
// Requirements: Requirement 1 (Player Authentication)
// Design Reference: Authentication Service - platform token authentication
// Task: 1.2.4 - Implement platform token authentication
func (s *ApiServer) AuthenticateSteamMMORPG(ctx context.Context, in *api.AuthenticateSteamRequest) (*api.Session, error) {
	// Extract client IP for rate limiting
	ip, _ := extractClientAddressFromContext(s.logger, ctx)

	// Check rate limiting - use "steam" as identifier since we don't have steam_id yet
	identifier := "steam:" + ip
	if !s.loginAttemptCache.Allow(identifier, ip) {
		return nil, status.Error(codes.ResourceExhausted, "Try again later.")
	}

	// Before hook (reuse standard Steam auth before hook)
	if fn := s.runtime.BeforeAuthenticateSteam(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	// Check if Steam authentication is configured
	if s.config.GetSocial().Steam.PublisherKey == "" || s.config.GetSocial().Steam.AppID == 0 {
		return nil, status.Error(codes.FailedPrecondition, "Steam authentication is not configured.")
	}

	// Validate Steam session ticket
	if in.Account == nil || in.Account.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "Steam session ticket is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	// Authenticate using MMORPG accounts table
	accountID, dbUsername, permissions, created, err := AuthenticateSteamMMORPG(ctx, s.logger, s.db, s.socialClient, s.config.GetSocial().Steam.AppID, s.config.GetSocial().Steam.PublisherKey, in.Account.Token, username, create)
	if err != nil {
		// Add failed attempt on authentication error
		if lockout, until := s.loginAttemptCache.Add(identifier, ip); lockout != LockoutTypeNone {
			s.logger.Warn("MMORPG Steam authentication lockout triggered", zap.String("ip", ip), zap.Time("locked_until", until))
		}
		return nil, err
	}

	// Reset attempts on successful authentication
	s.loginAttemptCache.Reset(identifier)

	// Generate MMORPG JWT token with permissions
	tokenExpirySec := s.config.GetSession().TokenExpirySec
	token, tokenID, expiresAt := GenerateMMORPGToken(
		s.config.GetSession().EncryptionKey,
		accountID,
		dbUsername,
		permissions,
		tokenExpirySec,
	)

	session := &api.Session{
		Created: created,
		Token:   token,
	}

	// After hook (reuse standard Steam auth after hook)
	if fn := s.runtime.AfterAuthenticateSteam(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(accountID))
			ctx = populateCtx(ctx, uid, dbUsername, tokenID, in.Account.Vars, expiresAt, time.Now().Unix())
			return fn(ctx, s.logger, accountID, dbUsername, in.Account.Vars, expiresAt, clientIP, clientPort, session, in)
		}

		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateFacebook(ctx context.Context, in *api.AuthenticateFacebookRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateFacebook(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if in.Account == nil || in.Account.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "Facebook access token is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, created, err := AuthenticateFacebook(ctx, s.logger, s.db, s.socialClient, s.config.GetSocial().FacebookLimitedLogin.AppId, in.Account.Token, username, create)
	if err != nil {
		return nil, err
	}

	// Import friends if requested.
	if in.Sync != nil && in.Sync.Value {
		_ = importFacebookFriends(ctx, s.logger, s.db, s.tracker, s.router, s.socialClient, uuid.FromStringOrNil(dbUserID), dbUsername, in.Account.Token, false)
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateFacebook(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, username, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateFacebookInstantGame(ctx context.Context, in *api.AuthenticateFacebookInstantGameRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateFacebookInstantGame(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if in.Account == nil || in.Account.SignedPlayerInfo == "" {
		return nil, status.Error(codes.InvalidArgument, "Signed Player Info for a Facebook Instant Game is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, created, err := AuthenticateFacebookInstantGame(ctx, s.logger, s.db, s.socialClient, s.config.GetSocial().FacebookInstantGame.AppSecret, in.Account.SignedPlayerInfo, username, create)
	if err != nil {
		return nil, err
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateFacebookInstantGame(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, username, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateGameCenter(ctx context.Context, in *api.AuthenticateGameCenterRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateGameCenter(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if in.Account == nil {
		return nil, status.Error(codes.InvalidArgument, "GameCenter access credentials are required.")
	} else if in.Account.BundleId == "" {
		return nil, status.Error(codes.InvalidArgument, "GameCenter bundle ID is required.")
	} else if in.Account.PlayerId == "" {
		return nil, status.Error(codes.InvalidArgument, "GameCenter player ID is required.")
	} else if in.Account.PublicKeyUrl == "" {
		return nil, status.Error(codes.InvalidArgument, "GameCenter public key URL is required.")
	} else if in.Account.Salt == "" {
		return nil, status.Error(codes.InvalidArgument, "GameCenter salt is required.")
	} else if in.Account.Signature == "" {
		return nil, status.Error(codes.InvalidArgument, "GameCenter signature is required.")
	} else if in.Account.TimestampSeconds == 0 {
		return nil, status.Error(codes.InvalidArgument, "GameCenter timestamp is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, created, err := AuthenticateGameCenter(ctx, s.logger, s.db, s.socialClient, in.Account.PlayerId, in.Account.BundleId, in.Account.TimestampSeconds, in.Account.Salt, in.Account.Signature, in.Account.PublicKeyUrl, username, create)
	if err != nil {
		return nil, err
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateGameCenter(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, username, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateGoogle(ctx context.Context, in *api.AuthenticateGoogleRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateGoogle(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if in.Account == nil || in.Account.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "Google access token is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, created, err := AuthenticateGoogle(ctx, s.logger, s.db, s.socialClient, in.Account.Token, username, create)
	if err != nil {
		return nil, err
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateGoogle(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, username, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func (s *ApiServer) AuthenticateSteam(ctx context.Context, in *api.AuthenticateSteamRequest) (*api.Session, error) {
	// Before hook.
	if fn := s.runtime.BeforeAuthenticateSteam(); fn != nil {
		beforeFn := func(clientIP, clientPort string) error {
			result, err, code := fn(ctx, s.logger, "", "", nil, 0, clientIP, clientPort, in)
			if err != nil {
				return status.Error(code, err.Error())
			}
			if result == nil {
				// If result is nil, requested resource is disabled.
				s.logger.Warn("Intercepted a disabled resource.", zap.Any("resource", ctx.Value(ctxFullMethodKey{}).(string)))
				return status.Error(codes.NotFound, "Requested resource was not found.")
			}
			in = result
			return nil
		}

		// Execute the before function lambda wrapped in a trace for stats measurement.
		err := traceApiBefore(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), beforeFn)
		if err != nil {
			return nil, err
		}
	}

	if s.config.GetSocial().Steam.PublisherKey == "" || s.config.GetSocial().Steam.AppID == 0 {
		return nil, status.Error(codes.FailedPrecondition, "Steam authentication is not configured.")
	}

	if in.Account == nil || in.Account.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "Steam access token is required.")
	}

	username := in.Username
	if username == "" {
		username = generateUsername()
	} else if invalidUsernameRegex.MatchString(username) {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, no spaces or control characters allowed.")
	} else if len(username) > 128 {
		return nil, status.Error(codes.InvalidArgument, "Username invalid, must be 1-128 bytes.")
	}

	create := in.Create == nil || in.Create.Value

	dbUserID, dbUsername, steamID, created, err := AuthenticateSteam(ctx, s.logger, s.db, s.socialClient, s.config.GetSocial().Steam.AppID, s.config.GetSocial().Steam.PublisherKey, in.Account.Token, username, create)
	if err != nil {
		return nil, err
	}

	// Import friends if requested.
	if in.Sync != nil && in.Sync.Value {
		_ = importSteamFriends(ctx, s.logger, s.db, s.tracker, s.router, s.socialClient, uuid.FromStringOrNil(dbUserID), dbUsername, s.config.GetSocial().Steam.PublisherKey, steamID, false)
	}

	if s.config.GetSession().SingleSession {
		s.sessionCache.RemoveAll(uuid.Must(uuid.FromString(dbUserID)))
	}

	tokenID := uuid.Must(uuid.NewV4()).String()
	tokenIssuedAt := time.Now().Unix()
	token, exp := generateToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	refreshToken, refreshExp := generateRefreshToken(s.config, tokenID, tokenIssuedAt, dbUserID, dbUsername, in.Account.Vars)
	s.sessionCache.Add(uuid.FromStringOrNil(dbUserID), exp, tokenID, refreshExp, tokenID)
	session := &api.Session{Created: created, Token: token, RefreshToken: refreshToken}

	// After hook.
	if fn := s.runtime.AfterAuthenticateSteam(); fn != nil {
		afterFn := func(clientIP, clientPort string) error {
			uid := uuid.Must(uuid.FromString(dbUserID))
			ctx = populateCtx(ctx, uid, username, tokenID, in.Account.Vars, exp, tokenIssuedAt)
			return fn(ctx, s.logger, dbUserID, dbUsername, in.Account.Vars, exp, clientIP, clientPort, session, in)
		}

		// Execute the after function lambda wrapped in a trace for stats measurement.
		traceApiAfter(ctx, s.logger, s.metrics, ctx.Value(ctxFullMethodKey{}).(string), afterFn)
	}

	return session, nil
}

func generateToken(config Config, tokenID string, tokenIssuedAt int64, userID, username string, vars map[string]string) (string, int64) {
	exp := time.Now().UTC().Add(time.Duration(config.GetSession().TokenExpirySec) * time.Second).Unix()
	return generateTokenWithExpiry(config.GetSession().EncryptionKey, tokenID, tokenIssuedAt, userID, username, vars, exp)
}

func generateRefreshToken(config Config, tokenID string, tokenIssuedAt int64, userID string, username string, vars map[string]string) (string, int64) {
	exp := time.Now().UTC().Add(time.Duration(config.GetSession().RefreshTokenExpirySec) * time.Second).Unix()
	return generateTokenWithExpiry(config.GetSession().RefreshEncryptionKey, tokenID, tokenIssuedAt, userID, username, vars, exp)
}

func generateTokenWithExpiry(signingKey, tokenID string, tokenIssuedAt int64, userID, username string, vars map[string]string, exp int64) (string, int64) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, &SessionTokenClaims{
		TokenId:   tokenID,
		UserId:    userID,
		Username:  username,
		Vars:      vars,
		ExpiresAt: exp,
		IssuedAt:  tokenIssuedAt,
	})
	signedToken, _ := token.SignedString([]byte(signingKey))
	return signedToken, exp
}

func generateUsername() string {
	const usernameAlphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	b := make([]byte, 10)
	for i := range b {
		b[i] = usernameAlphabet[rand.Intn(len(usernameAlphabet))]
	}
	return string(b)
}
