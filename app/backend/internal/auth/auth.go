// Package auth handles the Archangel backend's token authentication.
//
// Each paired device has its own long-lived token, generated once via
// GenerateToken and stored server-side only as a SHA-256 hash (never
// plaintext) - see internal/tokenstore. Every request except
// /api/v1/health must present a valid token via the X-Archangel-Token
// header. This is deliberately simple - no JWTs, no sessions, no bcrypt -
// because it protects a single-user personal tool that's already sitting
// behind a WireGuard tunnel; the token is defense-in-depth, not the only
// barrier, so a fast constant-time SHA-256 compare is the right amount of
// cryptography here, not more.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/http"
)

// GenerateToken returns a fresh random token (base64, shown to the user
// once) and its SHA-256 hash (hex, the only thing that gets stored).
func GenerateToken() (token string, hash string, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", "", fmt.Errorf("generating random token: %w", err)
	}
	token = base64.RawURLEncoding.EncodeToString(raw)
	hash = HashToken(token)
	return token, hash, nil
}

func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// Verifier reports whether a SHA-256 hex hash matches some currently valid
// token - a single legacy shared token, a per-device tokenstore.Store, or
// both combined - and, if so, which device it belongs to ("legacy" for the
// config.yaml token_hash). Callers should use a constant-time comparison
// per candidate hash, same discipline as the old single-hash check this
// replaced.
type Verifier func(hashHex string) (name string, ok bool)

type ctxKey struct{}

// DeviceName returns the paired device's name the auth middleware matched
// for this request ("" if the request didn't pass through Middleware).
func DeviceName(ctx context.Context) string {
	n, _ := ctx.Value(ctxKey{}).(string)
	return n
}

// WithDeviceName returns ctx carrying the given device name. Exposed so
// tests of downstream handlers can simulate an authenticated caller.
func WithDeviceName(ctx context.Context, name string) context.Context {
	return context.WithValue(ctx, ctxKey{}, name)
}

// Middleware rejects any request that doesn't present a token verify
// accepts.
func Middleware(verify Verifier, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("X-Archangel-Token")
		if token == "" {
			// WebSocket handshakes can't always set custom headers, so the
			// terminal/stats endpoints also accept the token as a query
			// param. Anything accepting it this way must treat the URL as
			// sensitive (not logged verbatim) - see terminal package.
			token = r.URL.Query().Get("token")
		}

		if token == "" {
			http.Error(w, "missing token", http.StatusUnauthorized)
			return
		}

		name, ok := verify(HashToken(token))
		if !ok {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r.WithContext(WithDeviceName(r.Context(), name)))
	})
}
