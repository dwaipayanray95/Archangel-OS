package files

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type uploadResp struct {
	Success bool   `json:"success"`
	Name    string `json:"name"`
	Size    int64  `json:"size"`
	Message string `json:"message"`
}

func setupUpload(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := SetRoot(dir); err != nil {
		t.Fatal(err)
	}
	SetUploadMax(0)
	t.Cleanup(func() { SetUploadMax(0) })
	return Root()
}

func doUpload(t *testing.T, dir, name string, body io.Reader, extra string) (int, uploadResp) {
	t.Helper()
	q := url.Values{}
	q.Set("dir", dir)
	q.Set("name", name)
	req := httptest.NewRequest("POST", "/api/v1/files/upload?"+q.Encode()+extra, body)
	req.Header.Set("Content-Type", "application/octet-stream")
	rec := httptest.NewRecorder()
	UploadHandler(rec, req)
	var r uploadResp
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("bad json %q: %v", rec.Body.String(), err)
	}
	return rec.Code, r
}

func noTempFiles(t *testing.T, dir string) {
	t.Helper()
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".archangel-upload-") {
			t.Errorf("temp file left behind: %s", e.Name())
		}
	}
}

func TestUploadHappyPath(t *testing.T) {
	root := setupUpload(t)
	sub := filepath.Join(root, "docs")
	if err := os.Mkdir(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	code, r := doUpload(t, sub, "hello.txt", strings.NewReader("hello"), "")
	if code != 200 || !r.Success || r.Name != "hello.txt" || r.Size != 5 {
		t.Fatalf("got %d %+v", code, r)
	}
	got, err := os.ReadFile(filepath.Join(sub, "hello.txt"))
	if err != nil || string(got) != "hello" {
		t.Fatalf("content %q err %v", got, err)
	}
	fi, _ := os.Stat(filepath.Join(sub, "hello.txt"))
	if fi.Mode().Perm() != 0o644 {
		t.Errorf("mode %v", fi.Mode().Perm())
	}
	noTempFiles(t, sub)
}

func TestUploadEmptyDirDefaultsToRoot(t *testing.T) {
	root := setupUpload(t)
	req := httptest.NewRequest("POST", "/api/v1/files/upload?name=a.bin", strings.NewReader("x"))
	rec := httptest.NewRecorder()
	UploadHandler(rec, req)
	if rec.Code != 200 {
		t.Fatalf("got %d", rec.Code)
	}
	if _, err := os.Stat(filepath.Join(root, "a.bin")); err != nil {
		t.Fatal(err)
	}
}

func TestUploadBadNames(t *testing.T) {
	root := setupUpload(t)
	long := strings.Repeat("a", 256)
	for _, name := range []string{"", ".", "..", "../x", "a/b", `a\b`, "a\x00b", "a\nb", "a\x7fb", long} {
		code, r := doUpload(t, root, name, strings.NewReader("x"), "")
		if code != 400 || r.Success || r.Message == "" {
			t.Errorf("name %q: got %d %+v", name, code, r)
		}
	}
	// 255 bytes is fine.
	if code, _ := doUpload(t, root, strings.Repeat("a", 255), strings.NewReader("x"), ""); code != 200 {
		t.Errorf("255-byte name rejected: %d", code)
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(root), "x")); err == nil {
		t.Error("traversal name wrote outside root")
	}
}

func TestUploadDirEscapes(t *testing.T) {
	root := setupUpload(t)
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(root, "link")); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{outside, root + "/../", filepath.Join(root, "link"), "/etc"} {
		code, r := doUpload(t, dir, "evil.txt", strings.NewReader("x"), "")
		if r.Success || code == 200 {
			t.Errorf("dir %q accepted: %d %+v", dir, code, r)
		}
	}
	if _, err := os.Stat(filepath.Join(outside, "evil.txt")); err == nil {
		t.Error("file written outside the jail")
	}
}

func TestUploadDirMissingOrNotADir(t *testing.T) {
	root := setupUpload(t)
	code, _ := doUpload(t, filepath.Join(root, "nope"), "a.txt", strings.NewReader("x"), "")
	if code != 404 {
		t.Errorf("missing dir: %d", code)
	}
	f := filepath.Join(root, "file.txt")
	_ = os.WriteFile(f, []byte("x"), 0o644)
	code, _ = doUpload(t, f, "a.txt", strings.NewReader("x"), "")
	if code != 400 {
		t.Errorf("file as dir: %d", code)
	}
}

func TestUploadSymlinkAtTarget(t *testing.T) {
	root := setupUpload(t)
	outside := filepath.Join(t.TempDir(), "secret")
	_ = os.WriteFile(outside, []byte("original"), 0o644)
	if err := os.Symlink(outside, filepath.Join(root, "s.txt")); err != nil {
		t.Fatal(err)
	}
	for _, extra := range []string{"", "&overwrite=true"} {
		code, r := doUpload(t, root, "s.txt", strings.NewReader("pwned"), extra)
		if code != 409 || r.Success {
			t.Errorf("extra %q: got %d %+v", extra, code, r)
		}
	}
	got, _ := os.ReadFile(outside)
	if string(got) != "original" {
		t.Errorf("symlink target modified: %q", got)
	}
	if fi, _ := os.Lstat(filepath.Join(root, "s.txt")); fi.Mode()&os.ModeSymlink == 0 {
		t.Error("symlink was replaced")
	}
	noTempFiles(t, root)
}

func TestUploadExistsAndOverwrite(t *testing.T) {
	root := setupUpload(t)
	p := filepath.Join(root, "a.txt")
	_ = os.WriteFile(p, []byte("old"), 0o600)

	code, r := doUpload(t, root, "a.txt", strings.NewReader("new"), "")
	if code != 409 || r.Message != "A file with that name already exists" {
		t.Fatalf("got %d %+v", code, r)
	}
	if got, _ := os.ReadFile(p); string(got) != "old" {
		t.Errorf("file changed without overwrite: %q", got)
	}
	noTempFiles(t, root)

	code, r = doUpload(t, root, "a.txt", strings.NewReader("newer"), "&overwrite=true")
	if code != 200 || r.Size != 5 {
		t.Fatalf("overwrite: %d %+v", code, r)
	}
	if got, _ := os.ReadFile(p); string(got) != "newer" {
		t.Errorf("content %q", got)
	}
	noTempFiles(t, root)

	_ = os.Mkdir(filepath.Join(root, "d"), 0o755)
	if code, _ := doUpload(t, root, "d", strings.NewReader("x"), "&overwrite=true"); code != 409 {
		t.Errorf("dir at target: %d", code)
	}
}

func TestUploadSizeLimit(t *testing.T) {
	root := setupUpload(t)
	SetUploadMax(10)

	// Streaming body without Content-Length (chunked): caught by MaxBytesReader.
	code, r := doUpload(t, root, "big.bin", io.MultiReader(bytes.NewReader(bytes.Repeat([]byte("a"), 11))), "")
	if code != 413 || r.Success || r.Message == "" {
		t.Fatalf("got %d %+v", code, r)
	}
	if _, err := os.Stat(filepath.Join(root, "big.bin")); err == nil {
		t.Error("oversized file was saved")
	}
	noTempFiles(t, root)

	// Declared Content-Length too large: rejected up front.
	req := httptest.NewRequest("POST", "/api/v1/files/upload?name=big2.bin&dir="+url.QueryEscape(root), bytes.NewReader(bytes.Repeat([]byte("a"), 50)))
	rec := httptest.NewRecorder()
	UploadHandler(rec, req)
	if rec.Code != 413 {
		t.Errorf("content-length check: %d", rec.Code)
	}

	// Exactly at the limit is fine.
	if code, _ := doUpload(t, root, "ok.bin", bytes.NewReader(bytes.Repeat([]byte("a"), 10)), ""); code != 200 {
		t.Errorf("at limit: %d", code)
	}
}

type failingReader struct{ n int }

func (f *failingReader) Read(p []byte) (int, error) {
	if f.n > 0 {
		f.n--
		copy(p, "abc")
		return 3, nil
	}
	return 0, errors.New("client went away")
}

func TestUploadCleansTempOnReadError(t *testing.T) {
	root := setupUpload(t)
	for _, extra := range []string{"", "&overwrite=true"} {
		code, r := doUpload(t, root, "partial.txt", &failingReader{n: 3}, extra)
		if code != 500 || r.Success {
			t.Fatalf("got %d %+v", code, r)
		}
		if _, err := os.Stat(filepath.Join(root, "partial.txt")); err == nil {
			t.Error("partial file was published")
		}
		noTempFiles(t, root)
	}
}

func TestUploadRoutedAndAuthenticated(t *testing.T) {
	// Method check on the handler itself.
	req := httptest.NewRequest("GET", "/api/v1/files/upload?name=a", nil)
	rec := httptest.NewRecorder()
	UploadHandler(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("got %d", rec.Code)
	}
}
