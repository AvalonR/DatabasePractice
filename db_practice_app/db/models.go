package db

import (
	"database/sql"
	"time"
)

// --- Map & Infrastructure ---

type Node struct {
	ID          int     `json:"id"`
	XCoord      float64 `json:"x_coord"`
	YCoord      float64 `json:"y_coord"`
	Label       string  `json:"label"`
	MapRegionID *int    `json:"map_region_id,omitempty"`
}

type Edge struct {
	ID            int     `json:"id"`
	NodeAId       int     `json:"node_a_id"`
	NodeBId       int     `json:"node_b_id"`
	DistanceUnits float64 `json:"distance_units"`
	SpeedLimit    int     `json:"speed_limit"`
	MapRegionID   *int    `json:"map_region_id,omitempty"`
}

type MapRegion struct {
	ID         int    `json:"id"`
	RegionName string `json:"region_name"`
	RiskLevel  string `json:"risk_level"` // Low, Medium, High
}

// --- People & Security ---

type Customer struct {
	ID        int    `json:"id"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Email     string `json:"email"`
	Phone     string `json:"phone"`
}

type Staff struct {
	ID        int       `json:"id"`
	FirstName string    `json:"first_name"`
	LastName  string    `json:"last_name"`
	Position  string    `json:"position"`
	HireDate  time.Time `json:"hire_date"`
}

type User struct {
	ID           int           `json:"id"`
	Username     string        `json:"username"`
	PasswordHash string        `json:"-"`
	RoleID       int           `json:"role_id"`
	StaffID      sql.NullInt64 `json:"staff_id"`
	CustomerID   sql.NullInt64 `json:"customer_id"`
}

type Role struct {
	ID       int    `json:"id"`
	RoleName string `json:"role_name"`
}

type Permission struct {
	ID      int    `json:"id"`
	PermKey string `json:"perm_key"`
}

// --- Logistics & Fleet ---

type VehicleType struct {
	ID          int     `json:"id"`
	TypeName    string  `json:"type_name"`
	FuelRate    float64 `json:"fuel_rate"`
	MaxCapacity float64 `json:"max_capacity"`
	PricePerKg  float64 `json:"price_per_kg"`
}

type Vehicle struct {
	ID            int    `json:"id"`
	TypeID        int    `json:"type_id"`
	LicensePlate  string `json:"license_plate"`
	CurrentStatus string `json:"current_status"`
}

type Route struct {
	ID            int       `json:"id"`
	VehicleID     int       `json:"vehicle_id"`
	DriverID      int       `json:"driver_id"`
	PlannedDate   time.Time `json:"planned_date"`
	TotalDistance float64   `json:"total_distance"`
	Status        string    `json:"status"`
}

type RouteSegment struct {
	ID            int `json:"id"`
	RouteID       int `json:"route_id"`
	EdgeID        int `json:"edge_id"`
	SequenceOrder int `json:"sequence_order"`
}

// --- Logs & Audits ---

type MaintenanceLog struct {
	ID          int       `json:"id"`
	VehicleID   int       `json:"vehicle_id"`
	ServiceDate time.Time `json:"service_date"`
	Description string    `json:"description"`
	Cost        float64   `json:"cost"`
}

type SystemAuditLog struct {
	ID              int       `json:"id"`
	UserID          int       `json:"user_id"`
	ActionPerformed string    `json:"action_performed"`
	ActionTimestamp time.Time `json:"action_timestamp"`
}

type NetworkData struct {
	Nodes []Node `json:"nodes"`
	Edges []Edge `json:"edges"`
}
