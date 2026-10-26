package files

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync/atomic"
	"unicode/utf8"
)

// DefaultUploadMaxBytes is the per-file upload size limit (2 GiB) used
// when config.yaml doesn't set upload_max_bytes.
const DefaultUploadMaxBytes int64 = 2 << 30

const maxNameBytes = 255

var uploadMaxBytes atomic.Int64

func init() { uploadMaxBytes.Store(DefaultUploadMaxBytes) }

// SetUploadMax overrides the upload size limit. Zero or negative keeps
// the default.
func SetUploadMax(n int64) {
	if n <= 0 {
		n = DefaultUploadMaxBytes
	}
	uploadMaxBytes.Store(n)
}

// uploadError carries the HTTP status and the user-facing message.
type uploadError struct {
	status int
	msg    string
}

func (e *uploadError) Error() string { return e.msg }

func uerr(status int, format string, a ...any) *uploadError {
	return &uploadError{status: status, msg: fmt.Sprintf(format, a...)}
}

// validateUploadName rejects anything that is not a plain file name.
func validateUploadName(name string) error {
	if name == "" {
		return errors.New("A file name is required")
	}
	if len(name) > maxNameBytes {
		return errors.New("That file name is too long")
	}
	if name == "." || name == ".." {
		return errors.New("That file name is not allowed")
	}
	if !utf8.ValidString(name) {
		return errors.New("That file name is not valid text")
	}
	for _, r := range name {
		if r == '/' || r == '\\' || r == 0 || r < 0x20 || r == 0x7f {
			return errors.New("That file name has characters that are not allowed")
		}
	}
	return nil
}

// SaveUpload streams body into dir/name inside the jail and returns the
// number of bytes written.
//
// The data goes to a temp file in the destination directory first, is
// fsynced, and is then moved into place, so readers never see a partial
// file. With overwrite=false the final step is a hard link (which fails
// atomically with EEXIST), so two concurrent uploads of the same name
// cannot clobber each other. On filesystems without hard links it falls
// back to check-then-rename, where a file created by someone else in the
// few microseconds between the check and the rename is replaced; that is
// acceptable for a single-owner server. With overwrite=true the final
// rename replaces the target atomically. A symlink at the target is
// never followed or replaced.
func SaveUpload(dir, name string, body io.Reader, overwrite bool) (int64, error) {
	if err := validateUploadName(name); err != nil {
		return 0, uerr(http.StatusBadRequest, "%s", err.Error())
	}
	resolvedDir, err := resolvePath(dir)
	if err != nil {
		return 0, uerr(http.StatusForbidden, "That folder is outside the area Files can use")
	}
	info, err := os.Stat(resolvedDir)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, uerr(http.StatusNotFound, "That folder doesn't exist")
		}
		return 0, uerr(http.StatusInternalServerError, "Couldn't open that folder")
	}
	if !info.IsDir() {
		return 0, uerr(http.StatusBadRequest, "That path is not a folder")
	}

	target := filepath.Join(resolvedDir, name)
	if err := checkTarget(target, overwrite); err != nil {
		return 0, err
	}

	tmp, err := os.CreateTemp(resolvedDir, ".archangel-upload-*")
	if err != nil {
		return 0, uerr(http.StatusInternalServerError, "Couldn't write to that folder")
	}
	tmpName := tmp.Name()
	published := false
	defer func() {
		if !published {
			_ = tmp.Close()
		}
		// On success without overwrite this removes the temp hard link;
		// on overwrite the temp name was renamed away already.
		_ = os.Remove(tmpName)
	}()

	n, err := io.Copy(tmp, body)
	if err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			return 0, uerr(http.StatusRequestEntityTooLarge, "That file is too big (limit %s)", FormatBytes(mbe.Limit))
		}
		return 0, uerr(http.StatusInternalServerError, "The upload was interrupted")
	}
	if err := tmp.Sync(); err != nil {
		return 0, uerr(http.StatusInternalServerError, "Couldn't save the file")
	}
	if err := tmp.Close(); err != nil {
		published = true // already closed
		return 0, uerr(http.StatusInternalServerError, "Couldn't save the file")
	}
	published = true // closed; nothing more to close
	if err := os.Chmod(tmpName, 0o644); err != nil {
		return 0, uerr(http.StatusInternalServerError, "Couldn't save the file")
	}

	// Re-check right before publishing (a symlink may have appeared).
	if err := checkTarget(target, overwrite); err != nil {
		return 0, err
	}
	if overwrite {
		if err := os.Rename(tmpName, target); err != nil {
			return 0, uerr(http.StatusInternalServerError, "Couldn't save the file")
		}
		return n, nil
	}
	if err := os.Link(tmpName, target); err != nil {
		if os.IsExist(err) {
			return 0, uerr(http.StatusConflict, "A file with that name already exists")
		}
		// No hard links on this filesystem: fall back to check-then-rename.
		if err := checkTarget(target, false); err != nil {
			return 0, err
		}
		if err := os.Rename(tmpName, target); err != nil {
			return 0, uerr(http.StatusInternalServerError, "Couldn't save the file")
		}
	}
	return n, nil
}

// checkTarget refuses symlinks and directories at the target and, unless
// overwrite is set, any existing file.
func checkTarget(target string, overwrite bool) error {
	fi, err := os.Lstat(target)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return uerr(http.StatusInternalServerError, "Couldn't check the destination")
	}
	switch {
	case fi.Mode()&os.ModeSymlink != 0:
		return uerr(http.StatusConflict, "A shortcut with that name already exists")
	case fi.IsDir():
		return uerr(http.StatusConflict, "A folder with that name already exists")
	case !fi.Mode().IsRegular():
		return uerr(http.StatusConflict, "Something with that name already exists")
	case !overwrite:
		return uerr(http.StatusConflict, "A file with that name already exists")
	}
	return nil
}

func writeUploadJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// UploadHandler handles POST /api/v1/files/upload?dir=...&name=...[&overwrite=true]
// with the raw file bytes as the body.
func UploadHandler(w http.ResponseWriter, r *http.Request) {
	fail := func(status int, msg string) {
		writeUploadJSON(w, status, map[string]any{"success": false, "message": msg})
	}
	if r.Method != http.MethodPost {
		fail(http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	q := r.URL.Query()
	dir := q.Get("dir")
	if dir == "" {
		dir = Root()
	}
	limit := uploadMaxBytes.Load()
	if r.ContentLength > limit {
		fail(http.StatusRequestEntityTooLarge, fmt.Sprintf("That file is too big (limit %s)", FormatBytes(limit)))
		return
	}
	body := http.MaxBytesReader(w, r.Body, limit)
	n, err := SaveUpload(dir, q.Get("name"), body, q.Get("overwrite") == "true")
	if err != nil {
		var ue *uploadError
		if errors.As(err, &ue) {
			fail(ue.status, ue.msg)
		} else {
			fail(http.StatusInternalServerError, "Couldn't save the file")
		}
		return
	}
	writeUploadJSON(w, http.StatusOK, map[string]any{"success": true, "name": q.Get("name"), "size": n})
}
