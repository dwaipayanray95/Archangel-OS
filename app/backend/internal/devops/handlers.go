package devops

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/dwaipayanray95/project-archangel/backend/internal/adminmode"
)

// ServicesHandler handles GET /api/v1/devops/services
func ServicesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	services, err := ListServices()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if services == nil {
		services = []ServiceItem{}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(services)
}

// ServiceActionHandler handles POST /api/v1/devops/services/{name}/{action}
func ServiceActionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	name := r.PathValue("name")
	action := r.PathValue("action")
	if name == "" || action == "" {
		http.Error(w, "missing name or action", http.StatusBadRequest)
		return
	}

	err := ServiceAction(name, action)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(actionErrorStatus(err))
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: "service " + name + " " + action + " triggered successfully",
	})
}

// ScheduledHandler handles GET /api/v1/devops/scheduled
func ScheduledHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	items, err := ListScheduled()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []ScheduledItem{}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(items)
}

// ScheduledRunHandler handles POST /api/v1/devops/scheduled/{name}/run
func ScheduledRunHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	name := r.PathValue("name")
	if name == "" {
		http.Error(w, "missing schedule name", http.StatusBadRequest)
		return
	}

	err := TriggerScheduled(name)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(actionErrorStatus(err))
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: "timer " + name + " triggered successfully",
	})
}

// ProxyHandler handles GET /api/v1/devops/proxy
func ProxyHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	items, err := ListProxy()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []ProxyItem{}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(items)
}

// ProxyTestHandler handles POST /api/v1/devops/proxy/{domain}/test
func ProxyTestHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	domain := r.PathValue("domain")
	ok, msg := TestProxyUpstream(domain)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: ok,
		Message: msg,
	})
}

// DeploymentsHandler handles GET /api/v1/devops/deployments
func DeploymentsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	items, err := ListDeployments()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []DeploymentItem{}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(items)
}

// DeploymentRunHandler handles POST /api/v1/devops/deployments/{name}/run
func DeploymentRunHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	name := r.PathValue("name")
	out, err := RunDeployment(name)

	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: err.Error(),
			Output:  out,
		})
		return
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: "deployment " + name + " executed successfully",
		Output:  out,
	})
}

// DeploymentCreateOrUpdateHandler handles POST /api/v1/devops/deployments
func DeploymentCreateOrUpdateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CreateDeploymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body: "+err.Error(), http.StatusBadRequest)
		return
	}

	if req.Name == "" {
		http.Error(w, "missing deployment script name", http.StatusBadRequest)
		return
	}

	err := CreateOrUpdateDeployment(req.Name, req.Content)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: "deployment script " + req.Name + " saved successfully",
	})
}

// DeploymentContentHandler handles GET /api/v1/devops/deployments/{name}/content
func DeploymentContentHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	name := r.PathValue("name")
	if name == "" {
		http.Error(w, "missing deployment script name", http.StatusBadRequest)
		return
	}

	content, err := GetDeploymentContent(name)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(DeploymentContentResponse{
		Name:    name,
		Content: content,
	})
}

// DeploymentDeleteHandler handles DELETE /api/v1/devops/deployments/{name}
func DeploymentDeleteHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	name := r.PathValue("name")
	if name == "" {
		http.Error(w, "missing deployment script name", http.StatusBadRequest)
		return
	}

	err := DeleteDeployment(name)
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: "deployment script " + name + " deleted successfully",
	})
}

// actionErrorStatus maps a systemctl action error to an HTTP status: 403
// for deliberate refusals (lockout guards, Admin mode off), 500 otherwise.
func actionErrorStatus(err error) int {
	if errors.Is(err, ErrRefused) || errors.Is(err, adminmode.ErrOff) {
		return http.StatusForbidden
	}
	return http.StatusInternalServerError
}
