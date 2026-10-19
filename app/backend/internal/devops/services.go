package devops

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"time"

	"github.com/dwaipayanray95/project-archangel/backend/internal/adminmode"
)

var validUnitName = regexp.MustCompile(`^[a-zA-Z0-9@_.:-]+$`)

// managedUnits is the fixed allowlist of systemd units this app is allowed
// to inspect and act on. ServiceAction/TriggerScheduled must only ever
// target something in this set - without it, any string matching
// validUnitName's charset (which permits arbitrary unit names, including
// ssh.service or archangeld.service itself) would be handed straight to
// `systemctl <action> <name>`, turning "manage a few homelab services" into
// "manage anything on the box."
var managedUnits = map[string]bool{
	"caddy.service":        true,
	"docker.service":       true,
	"postgresql.service":   true,
	"wg-quick@wg0.service": true,
	// The real unit file is archangel.service; archangeld.service is kept
	// for hosts/clients that still use the old name.
	"archangel.service":           true,
	"archangeld.service":          true,
	"unattended-upgrades.service": true,
	"ssh.service":                 true,
	"cron.service":                true,
}

// lockoutUnits can be restarted but never stopped from the app: stopping
// SSH, the WireGuard tunnel, or archangeld itself would cut the user off
// from the server with no way back in except the provider's console.
var lockoutUnits = map[string]bool{
	"ssh.service":          true,
	"wg-quick@wg0.service": true,
	"archangeld.service":   true,
	"archangel.service":    true,
}

// ErrRefused marks an action the backend refuses on purpose (as opposed to
// one that failed); handlers map it to 403.
var ErrRefused = errors.New("refused")

// refusedError carries a user-facing message verbatim (no "refused:" prefix)
// while still matching errors.Is(err, ErrRefused).
type refusedError struct{ msg string }

func (e refusedError) Error() string        { return e.msg }
func (e refusedError) Is(target error) bool { return target == ErrRefused }

// ListServices inspects systemd service units.
func ListServices() ([]ServiceItem, error) {
	if runtime.GOOS != "linux" {
		return listLocalFallbackServices()
	}

	// Check if systemctl binary exists
	systemctl, err := exec.LookPath("systemctl")
	if err != nil {
		return listLocalFallbackServices()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	// List targeted services or common homelab units
	units := managedUnitNames()

	cmd := exec.CommandContext(ctx, systemctl, append([]string{"show", "--property=Id,Description,LoadState,ActiveState,SubState,ActiveEnterTimestamp"}, units...)...)
	out, err := cmd.Output()
	if err != nil {
		return listLocalFallbackServices()
	}

	return parseSystemctlShow(string(out)), nil
}

func parseSystemctlShow(raw string) []ServiceItem {
	var items []ServiceItem
	scanner := bufio.NewScanner(strings.NewReader(raw))

	current := ServiceItem{}
	activeTs := ""

	flush := func() {
		if current.Name != "" && current.LoadState != "not-found" {
			current.Ok = current.ActiveState == "active"
			current.Status = current.ActiveState
			if current.Status == "" {
				current.Status = "unknown"
			}

			metaParts := []string{current.SubState}
			if activeTs != "" {
				metaParts = append(metaParts, "since "+activeTs)
			}
			current.Meta = strings.Join(metaParts, " · ")

			if current.Ok {
				current.Actions = []string{"Restart", "Stop", "Logs"}
			} else {
				current.Actions = []string{"Start", "Logs"}
			}
			items = append(items, current)
		}
		current = ServiceItem{}
		activeTs = ""
	}

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			flush()
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		k, v := parts[0], parts[1]

		switch k {
		case "Id":
			current.Name = v
		case "Description":
			current.Description = v
		case "LoadState":
			current.LoadState = v
		case "ActiveState":
			current.ActiveState = v
		case "SubState":
			current.SubState = v
		case "ActiveEnterTimestamp":
			if v != "" {
				activeTs = v
				// Abbreviate if too long (e.g. Fri 2026-09-11 12:00:00 UTC)
				if len(activeTs) > 25 {
					activeTs = activeTs[:25]
				}
			}
		}
	}
	flush()

	if len(items) == 0 {
		fallback, _ := listLocalFallbackServices()
		return fallback
	}
	return items
}

// managedUnitNames returns managedUnits' keys.
func managedUnitNames() []string {
	names := make([]string, 0, len(managedUnits))
	for name := range managedUnits {
		names = append(names, name)
	}
	return names
}

// ServiceAction triggers systemctl start, stop, or restart.
func ServiceAction(name, action string) error {
	if !validUnitName.MatchString(name) || !managedUnits[name] {
		return fmt.Errorf("invalid service name")
	}

	switch action {
	case "start", "stop", "restart":
	default:
		return fmt.Errorf("unsupported action: %s", action)
	}

	if err := checkLockout(name, action); err != nil {
		return err
	}

	return systemctlRun(action, name)
}

// checkLockout refuses "stop" for units whose absence would strand the user.
func checkLockout(name, action string) error {
	if action == "stop" && lockoutUnits[name] {
		return refusedError{fmt.Sprintf("Stopping %s would cut you off from your server; restart is allowed", name)}
	}
	return nil
}

// systemctlRun runs `sudo -n systemctl <action> <unit>`. A var so tests can
// observe calls without touching the host. Root is needed because the
// service runs unprivileged; when Admin mode is off the error says so.
var systemctlRun = func(action, unit string) error {
	if runtime.GOOS != "linux" {
		return nil // Simulated on non-Linux dev machines
	}
	if _, err := exec.LookPath("systemctl"); err != nil {
		return fmt.Errorf("systemctl not available on this host")
	}
	if _, err := adminmode.Run(10*time.Second, "systemctl", action, unit); err != nil {
		if errors.Is(err, adminmode.ErrOff) {
			return err
		}
		return fmt.Errorf("%s failed: %v", action, err)
	}
	return nil
}

// listLocalFallbackServices inspects standard service files or daemon presence.
func listLocalFallbackServices() ([]ServiceItem, error) {
	// Detect if Docker or Archangel is running on this machine
	dockerActive := false
	if _, err := os.Stat("/var/run/docker.sock"); err == nil {
		dockerActive = true
	}

	return []ServiceItem{
		{
			Name:        "docker.service",
			Description: "Docker Application Container Engine",
			ActiveState: func() string {
				if dockerActive {
					return "active"
				}
				return "inactive"
			}(),
			Status: func() string {
				if dockerActive {
					return "active"
				}
				return "inactive"
			}(),
			Ok:      dockerActive,
			Meta:    "local daemon socket check",
			Actions: []string{"Restart", "Logs"},
		},
		{
			Name:        "archangeld.service",
			Description: "Archangel Host Control Daemon",
			ActiveState: "active",
			Status:      "active",
			Ok:          true,
			Meta:        "current daemon instance",
			Actions:     []string{"Restart", "Logs"},
		},
	}, nil
}
