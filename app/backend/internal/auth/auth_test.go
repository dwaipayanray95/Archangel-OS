package auth

import (
	"context"
	"crypto/subtle"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestGenerateTokenHashMatches(t *testing.T) {
	token, hash, err := GenerateToken()
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	if token == "" || hash == "" {
		t.Fatal("expected non-empty token and hash")
	}
	if got := HashToken(token); got != hash {
		t.Fatalf("HashToken(token) = %q, want %q", got, hash)
	}
}

func TestGenerateTokenIsRandom(t *testing.T) {
	t1, _, _ := GenerateToken()
	t2, _, _ := GenerateToken()
	if t1 == t2 {
		t.Fatal("two calls to GenerateToken produced the same token")
	}
}

func TestMiddleware(t *testing.T) {
	realToken, realHash, err := GenerateToken()
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	verify := func(hash string) (string, bool) {
		return "phone", subtle.ConstantTimeCompare([]byte(hash), []byte(realHash)) == 1
	}
	handler := Middleware(verify, next)

	cases := []struct {
		name       string
		setupReq   func(r *http.Request)
		wantStatus int
	}{
		{
			name:       "no token",
			setupReq:   func(r *http.Request) {},
			wantStatus: http.StatusUnauthorized,
		},
		{
			name: "wrong token in header",
			setupReq: func(r *http.Request) {
				r.Header.Set("X-Archangel-Token", "not-the-right-token")
			},
			wantStatus: http.StatusUnauthorized,
		},
		{
			name: "correct token in header",
			setupReq: func(r *http.Request) {
				r.Header.Set("X-Archangel-Token", realToken)
			},
			wantStatus: http.StatusOK,
		},
		{
			name: "correct token as query param (WS handshake path)",
			setupReq: func(r *http.Request) {
				q := r.URL.Query()
				q.Set("token", realToken)
				r.URL.RawQuery = q.Encode()
			},
			wantStatus: http.StatusOK,
		},
		{
			name: "hash from an unrelated token also generated should not authenticate",
			setupReq: func(r *http.Request) {
				otherToken, _, _ := GenerateToken()
				r.Header.Set("X-Archangel-Token", otherToken)
			},
			wantStatus: http.StatusUnauthorized,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/ws/terminal", nil)
			tc.setupReq(req)
			rec := httptest.NewRecorder()

			handler.ServeHTTP(rec, req)

			if rec.Code != tc.wantStatus {
				t.Errorf("status = %d, want %d", rec.Code, tc.wantStatus)
			}
		})
	}
}

func TestMiddlewareSetsDeviceName(t *testing.T) {
	token, hash, _ := GenerateToken()
	var got string
	h := Middleware(func(h string) (string, bool) { return "laptop", h == hash },
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { got = DeviceName(r.Context()) }))
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.Header.Set("X-Archangel-Token", token)
	h.ServeHTTP(httptest.NewRecorder(), req)
	if got != "laptop" {
		t.Errorf("DeviceName = %q, want laptop", got)
	}
	if DeviceName(context.Background()) != "" {
		t.Error("DeviceName on bare context should be empty")
	}
}
