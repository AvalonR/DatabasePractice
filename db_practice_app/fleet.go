package main

import (
	"db_practice_app/db"
	"errors"
	"fmt"
	"strings"
)

type VehicleDetail struct {
	ID            int     `json:"id"`
	TypeName      string  `json:"type_name"`
	LicensePlate  string  `json:"license_plate"`
	FuelRate      float64 `json:"fuel_rate"`
	MaxCapacity   float64 `json:"max_capacity"`
	PricePerKg    float64 `json:"price_per_kg"`
	CurrentStatus string  `json:"current_status"`
}

var validStatuses = map[string]bool{
	"Available":   true,
	"On Route":    true,
	"Maintenance": true,
	"Retired":     true,
}

func (a *App) GetAllVehicles() ([]VehicleDetail, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	if !a.hasPermission("manage_vehicles") {
		return nil, errors.New("permission denied")
	}

	rows, err := a.db.Query(`
		SELECT v.id, vt.type_name, v.license_plate,
		       vt.fuel_rate, vt.max_weight_capacity, vt.price_per_kg, v.current_status
		FROM vehicles v
		JOIN vehicle_types vt ON vt.id = v.type_id
	`)
	if err != nil {
		return nil, fmt.Errorf("query vehicles: %w", err)
	}
	defer rows.Close()

	var details []VehicleDetail
	for rows.Next() {
		var d VehicleDetail
		if err := rows.Scan(&d.ID, &d.TypeName, &d.LicensePlate,
			&d.FuelRate, &d.MaxCapacity, &d.PricePerKg, &d.CurrentStatus); err != nil {
			return nil, fmt.Errorf("scan vehicle: %w", err)
		}
		details = append(details, d)
	}
	return details, rows.Err()
}

func (a *App) GetVehicleTypes() ([]db.VehicleType, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	rows, err := a.db.Query("SELECT id, type_name, fuel_rate, max_weight_capacity, price_per_kg FROM vehicle_types")
	if err != nil {
		return nil, fmt.Errorf("query vehicle types: %w", err)
	}
	defer rows.Close()

	var types []db.VehicleType
	for rows.Next() {
		var t db.VehicleType
		if err := rows.Scan(&t.ID, &t.TypeName, &t.FuelRate, &t.MaxCapacity, &t.PricePerKg); err != nil {
			return nil, fmt.Errorf("scan vehicle type: %w", err)
		}
		types = append(types, t)
	}
	return types, rows.Err()
}

func (a *App) CreateVehicleType(name string, fuelRate float64, maxCapacity float64, pricePerKg float64) (*db.VehicleType, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	if !a.hasPermission("manage_vehicle_types") {
		return nil, errors.New("permission denied")
	}
	if name == "" {
		return nil, errors.New("type name is required")
	}
	if fuelRate <= 0 {
		return nil, errors.New("fuel rate must be positive")
	}
	if maxCapacity <= 0 {
		return nil, errors.New("max capacity must be positive")
	}
	if pricePerKg <= 0 {
		return nil, errors.New("price per kg must be positive")
	}
	result, err := a.db.Exec(
		"INSERT INTO vehicle_types (type_name, fuel_rate, max_weight_capacity, price_per_kg) VALUES (?, ?, ?, ?)",
		name, fuelRate, maxCapacity, pricePerKg,
	)
	if err != nil {
		return nil, fmt.Errorf("create vehicle type: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("get vehicle type id: %w", err)
	}
	return &db.VehicleType{
		ID:          int(id),
		TypeName:    name,
		FuelRate:    fuelRate,
		MaxCapacity: maxCapacity,
		PricePerKg:  pricePerKg,
	}, nil
}

func (a *App) UpdateVehicleType(id int, name string, fuelRate float64, maxCapacity float64, pricePerKg float64) error {
	if err := a.requireDB(); err != nil {
		return err
	}
	if !a.hasPermission("manage_vehicle_types") {
		return errors.New("permission denied")
	}
	if name == "" {
		return errors.New("type name is required")
	}
	if fuelRate <= 0 {
		return errors.New("fuel rate must be positive")
	}
	if maxCapacity <= 0 {
		return errors.New("max capacity must be positive")
	}
	if pricePerKg <= 0 {
		return errors.New("price per kg must be positive")
	}
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM vehicle_types WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check vehicle type: %w", err)
	}
	if !exists {
		return errors.New("vehicle type not found")
	}
	_, err = a.db.Exec(
		"UPDATE vehicle_types SET type_name = ?, fuel_rate = ?, max_weight_capacity = ?, price_per_kg = ? WHERE id = ?",
		name, fuelRate, maxCapacity, pricePerKg, id,
	)
	if err != nil {
		return fmt.Errorf("update vehicle type: %w", err)
	}
	return nil
}

func (a *App) DeleteVehicleType(id int) error {
	if err := a.requireDB(); err != nil {
		return err
	}
	if !a.hasPermission("manage_vehicle_types") {
		return errors.New("permission denied")
	}
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM vehicle_types WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check vehicle type: %w", err)
	}
	if !exists {
		return errors.New("vehicle type not found")
	}
	var vehicleCount int
	err = a.db.QueryRow("SELECT COUNT(*) FROM vehicles WHERE type_id = ?", id).Scan(&vehicleCount)
	if err != nil {
		return fmt.Errorf("check vehicles: %w", err)
	}
	if vehicleCount > 0 {
		return fmt.Errorf("cannot delete: %d vehicle(s) use this type. Reassign them first", vehicleCount)
	}
	_, err = a.db.Exec("DELETE FROM vehicle_types WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete vehicle type: %w", err)
	}
	return nil
}

func (a *App) CreateVehicle(typeID int, licensePlate string, status string) (*VehicleDetail, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	if !a.hasPermission("manage_vehicles") {
		return nil, errors.New("permission denied")
	}
	if licensePlate == "" {
		return nil, errors.New("license plate is required")
	}
	if !validStatuses[status] {
		return nil, fmt.Errorf("invalid status %q; must be one of: Available, On Route, Maintenance, Retired", status)
	}

	var typeName string
	var fuelRate, maxCap, pricePerKg float64
	err := a.db.QueryRow(
		"SELECT type_name, fuel_rate, max_weight_capacity, price_per_kg FROM vehicle_types WHERE id = ?", typeID,
	).Scan(&typeName, &fuelRate, &maxCap, &pricePerKg)
	if err != nil {
		return nil, errors.New("vehicle type not found")
	}

	res, err := a.db.Exec(
		"INSERT INTO vehicles (type_id, license_plate, current_status) VALUES (?, ?, ?)",
		typeID, licensePlate, status,
	)
	if err != nil {
		if strings.Contains(err.Error(), "Duplicate entry") {
			return nil, errors.New("license plate already exists")
		}
		return nil, fmt.Errorf("create vehicle: %w", err)
	}

	vid, err := res.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("get vehicle id: %w", err)
	}

	return &VehicleDetail{
		ID:            int(vid),
		TypeName:      typeName,
		LicensePlate:  licensePlate,
		FuelRate:      fuelRate,
		MaxCapacity:   maxCap,
		PricePerKg:    pricePerKg,
		CurrentStatus: status,
	}, nil
}

func (a *App) UpdateVehicle(id int, typeID int, licensePlate string, status string) error {
	if err := a.requireDB(); err != nil {
		return err
	}
	if !a.hasPermission("manage_vehicles") {
		return errors.New("permission denied")
	}
	if licensePlate == "" {
		return errors.New("license plate is required")
	}
	if !validStatuses[status] {
		return fmt.Errorf("invalid status %q; must be one of: Available, On Route, Maintenance, Retired", status)
	}

	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM vehicles WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check vehicle: %w", err)
	}
	if !exists {
		return errors.New("vehicle not found")
	}

	var typeExists bool
	err = a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM vehicle_types WHERE id = ?)", typeID).Scan(&typeExists)
	if err != nil {
		return fmt.Errorf("check type: %w", err)
	}
	if !typeExists {
		return errors.New("vehicle type not found")
	}

	_, err = a.db.Exec(
		"UPDATE vehicles SET type_id = ?, license_plate = ?, current_status = ? WHERE id = ?",
		typeID, licensePlate, status, id,
	)
	if err != nil {
		if strings.Contains(err.Error(), "Duplicate entry") {
			return errors.New("license plate already exists")
		}
		return fmt.Errorf("update vehicle: %w", err)
	}
	return nil
}

func (a *App) DeleteVehicle(id int) error {
	if err := a.requireDB(); err != nil {
		return err
	}
	if !a.hasPermission("manage_vehicles") {
		return errors.New("permission denied")
	}

	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM vehicles WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check vehicle: %w", err)
	}
	if !exists {
		return errors.New("vehicle not found")
	}

	var routeCount int
	err = a.db.QueryRow(
		"SELECT COUNT(*) FROM routes WHERE vehicle_id = ? AND status IN ('Planned', 'Active')", id,
	).Scan(&routeCount)
	if err != nil {
		return fmt.Errorf("check routes: %w", err)
	}
	if routeCount > 0 {
		return fmt.Errorf("cannot delete: vehicle is assigned to %d active route(s). Reassign them first", routeCount)
	}

	tx, err := a.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	_, err = tx.Exec("DELETE FROM maintenance_logs WHERE vehicle_id = ?", id)
	if err != nil {
		return fmt.Errorf("delete maintenance logs: %w", err)
	}

	_, err = tx.Exec("DELETE FROM vehicles WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete vehicle: %w", err)
	}

	return tx.Commit()
}
