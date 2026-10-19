package docker

import (
	"context"
	"sync"
	"time"
)

const (
	// statsRefreshEvery is how often the background poller refreshes
	// per-container CPU/memory.
	statsRefreshEvery = 5 * time.Second
	// statsMaxAge: a cached reading older than this is ignored rather than
	// shown, so a stalled poller never presents stale numbers as live.
	statsMaxAge = 30 * time.Second
	// statsConcurrency bounds simultaneous /stats calls to the Docker socket.
	statsConcurrency = 4
)

// Docker's /stats?stream=false blocks for about a second per container
// (it samples twice to compute CPU), so doing it inside the list request
// made the Containers tab slow. A background goroutine fills this cache
// instead and ListContainers just reads it.

type statEntry struct {
	cpu      float64
	memMb    int64
	memLabel string
	at       time.Time
}

type statsCache struct {
	mu      sync.RWMutex
	entries map[string]statEntry
}

func newStatsCache() *statsCache {
	return &statsCache{entries: map[string]statEntry{}}
}

var (
	globalStats     = newStatsCache()
	statsPollerOnce sync.Once
)

func (s *statsCache) put(id string, cpu float64, memMb int64, label string, at time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.entries[id] = statEntry{cpu: cpu, memMb: memMb, memLabel: label, at: at}
}

// prune drops entries for containers that no longer exist or aren't running.
func (s *statsCache) prune(keep map[string]bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for id := range s.entries {
		if !keep[id] {
			delete(s.entries, id)
		}
	}
}

// mergeStats fills CPU/Mem on running containers from the cache. Missing
// or too-old entries leave the "—"/0 defaults untouched - never fabricate
// a reading.
func mergeStats(items []ContainerItem, s *statsCache, now time.Time) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for i := range items {
		if !items[i].Running {
			continue
		}
		e, ok := s.entries[items[i].ID]
		if !ok || now.Sub(e.at) > statsMaxAge {
			continue
		}
		items[i].CPU = e.cpu
		items[i].MemMb = e.memMb
		items[i].MemLabel = e.memLabel
	}
}

// startStatsPoller launches the background refresher once.
func startStatsPoller() {
	statsPollerOnce.Do(func() {
		go func() {
			refreshStats()
			t := time.NewTicker(statsRefreshEvery)
			defer t.Stop()
			for range t.C {
				refreshStats()
			}
		}()
	})
}

// refreshStats does one polling pass using the package default client.
func refreshStats() {
	c := defaultClient
	if !c.IsAvailable() {
		globalStats.prune(nil)
		return
	}
	items, err := c.ListContainers()
	if err != nil {
		return
	}
	keep := map[string]bool{}
	var running []string
	for _, it := range items {
		if it.Running {
			keep[it.ID] = true
			running = append(running, it.ID)
		}
	}
	globalStats.prune(keep)

	sem := make(chan struct{}, statsConcurrency)
	var wg sync.WaitGroup
	for _, id := range running {
		wg.Add(1)
		sem <- struct{}{}
		go func(id string) {
			defer wg.Done()
			defer func() { <-sem }()
			ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
			defer cancel()
			cpu, memMb, label, err := c.ContainerStats(ctx, id)
			if err == nil {
				globalStats.put(id, cpu, memMb, label, time.Now())
			}
		}(id)
	}
	wg.Wait()
}
