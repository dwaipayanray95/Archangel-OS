package docker

import (
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
)

// privateIP is the address new containers' published ports bind to when the
// caller doesn't name one. main sets it to config's bind_addr (the
// WireGuard IP) via SetPrivateBindIP, so a container started from the app
// is reachable only through the tunnel by default instead of on every
// interface (Docker's own default, which also bypasses UFW because Docker
// writes its own iptables rules).
var (
	privateIPMu sync.RWMutex
	privateIP   string
)

// SetPrivateBindIP sets the default host IP for "host:container" port
// mappings. Called once from main with the WireGuard bind address.
func SetPrivateBindIP(ip string) {
	privateIPMu.Lock()
	defer privateIPMu.Unlock()
	privateIP = strings.TrimSpace(ip)
}

// privateBindIP returns the configured default publish address, falling
// back to loopback (fail closed) if main never set one.
func privateBindIP() string {
	privateIPMu.RLock()
	defer privateIPMu.RUnlock()
	if privateIP == "" || privateIP == "0.0.0.0" {
		return "127.0.0.1"
	}
	return privateIP
}

// PortSpec is one parsed entry of CreateContainerRequest.Ports.
type PortSpec struct {
	// ContainerPort is in Docker's "80/tcp" form.
	ContainerPort string
	// HostIP and HostPort are empty when the spec only exposes a port
	// without publishing it ("80").
	HostIP   string
	HostPort string
}

// ParsePortSpec parses "80", "8080:80" or "1.2.3.4:8080:80", each
// optionally with "/tcp" or "/udp" after the container port. A 2-part spec
// binds to defaultIP (the WireGuard address) so it stays private; making a
// port public requires the explicit 3-part form, e.g. "0.0.0.0:8080:80".
// Returns (nil, nil) for an empty spec.
func ParsePortSpec(raw, defaultIP string) (*PortSpec, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}

	parts := strings.Split(raw, ":")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}

	var hostIP, hostPort, contPort string
	switch len(parts) {
	case 1:
		contPort = parts[0]
	case 2:
		hostIP, hostPort, contPort = defaultIP, parts[0], parts[1]
	case 3:
		hostIP, hostPort, contPort = parts[0], parts[1], parts[2]
		if net.ParseIP(hostIP) == nil {
			return nil, fmt.Errorf("invalid host IP %q in port mapping %q", hostIP, raw)
		}
	default:
		return nil, fmt.Errorf("invalid port mapping %q", raw)
	}

	proto := "tcp"
	if i := strings.Index(contPort, "/"); i >= 0 {
		proto = strings.ToLower(contPort[i+1:])
		contPort = contPort[:i]
		if proto != "tcp" && proto != "udp" {
			return nil, fmt.Errorf("invalid protocol %q in port mapping %q (use tcp or udp)", proto, raw)
		}
	}
	if !validPort(contPort) {
		return nil, fmt.Errorf("invalid container port %q in port mapping %q", contPort, raw)
	}
	spec := &PortSpec{ContainerPort: contPort + "/" + proto}

	if len(parts) > 1 {
		if !validPort(hostPort) {
			return nil, fmt.Errorf("invalid host port %q in port mapping %q", hostPort, raw)
		}
		spec.HostIP = hostIP
		spec.HostPort = hostPort
	}
	return spec, nil
}

func validPort(s string) bool {
	n, err := strconv.Atoi(s)
	return err == nil && n >= 1 && n <= 65535 && s == strconv.Itoa(n)
}
