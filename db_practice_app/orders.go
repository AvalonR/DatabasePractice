package main

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"time"
)

type DeliveryInfo struct {
	ID          int     `json:"id"`
	RouteID     int     `json:"route_id"`
	Status      string  `json:"status"`
	ActualTime  *string `json:"actual_time,omitempty"`
	DriverName  *string `json:"driver_name,omitempty"`
	VehiclePlate *string `json:"vehicle_plate,omitempty"`
}

type OrderDetail struct {
	ID               int            `json:"id"`
	CustomerID       int            `json:"customer_id"`
	CustomerName     string         `json:"customer_name"`
	PickupNodeID     int            `json:"pickup_node_id"`
	PickupNodeLabel  string         `json:"pickup_node_label"`
	DropoffNodeID    int            `json:"dropoff_node_id"`
	DropoffNodeLabel string         `json:"dropoff_node_label"`
	OrderDate        string         `json:"order_date"`
	TotalWeight      float64        `json:"total_weight"`
	Status           string         `json:"status"`
	Deliveries       []DeliveryInfo `json:"deliveries"`
}

type OrderCreat struct {
	CustomerID    int     `json:"customer_id"`
	PickupNodeID  int     `json:"pickup_node_id"`
	DropoffNodeID int     `json:"dropoff_node_id"`
	TotalWeight   float64 `json:"total_weight"`
}

type OrderUpdate struct {
	ID            int     `json:"id"`
	PickupNodeID  int     `json:"pickup_node_id"`
	DropoffNodeID int     `json:"dropoff_node_id"`
	TotalWeight   float64 `json:"total_weight"`
}

type StaffInfo struct {
	ID        int    `json:"id"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
}

var validOrderStatuses = map[string]bool{
	"Draft": true, "Pending": true, "In Transit": true,
	"Delivered": true, "Failed": true, "Cancelled": true, "Returned": true,
}

var validDeliveryStatuses = map[string]bool{
	"Pending": true, "In Transit": true, "Delivered": true, "Failed": true,
}

func (a *App) GetOrders() ([]OrderDetail, error) {
	canViewAll := a.hasPermission("view_all_orders")
	canViewPersonal := a.hasPermission("view_personal_orders")
	if !canViewAll && !canViewPersonal {
		return nil, errors.New("permission denied")
	}

	var fromClause string
	var whereClause string
	var args []interface{}

	if !canViewAll && a.currentUser != nil {
		if a.currentUser.StaffID != nil {
			fromClause = "JOIN deliveries d2 ON d2.order_id = o.id JOIN routes r2 ON r2.id = d2.route_id AND r2.driver_id = ?"
			args = append(args, *a.currentUser.StaffID)
		} else if a.currentUser.CustomerID != nil {
			whereClause = "WHERE o.customer_id = ?"
			args = append(args, *a.currentUser.CustomerID)
		} else {
			return nil, errors.New("permission denied")
		}
	}

	query := fmt.Sprintf(`
		SELECT DISTINCT o.id, o.customer_id, CONCAT(c.first_name, ' ', c.last_name),
		       o.pickup_node_id, COALESCE(pn.label, ''),
		       o.dropoff_node_id, COALESCE(dn.label, ''),
		       o.order_date, o.total_weight, o.status
		FROM orders o
		JOIN customers c ON c.id = o.customer_id
		JOIN nodes pn ON pn.id = o.pickup_node_id
		JOIN nodes dn ON dn.id = o.dropoff_node_id
		%s
		%s
		ORDER BY o.id DESC
	`, fromClause, whereClause)

	rows, err := a.db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("query orders: %w", err)
	}
	defer rows.Close()

	orders := []OrderDetail{}
	var orderIDs []int
	orderMap := map[int]int{}

	for rows.Next() {
		var o OrderDetail
		var date time.Time
		if err := rows.Scan(&o.ID, &o.CustomerID, &o.CustomerName,
			&o.PickupNodeID, &o.PickupNodeLabel,
			&o.DropoffNodeID, &o.DropoffNodeLabel,
			&date, &o.TotalWeight, &o.Status); err != nil {
			return nil, fmt.Errorf("scan order: %w", err)
		}
		o.OrderDate = date.Format("2006-01-02 15:04")
		o.Deliveries = []DeliveryInfo{}
		orderMap[o.ID] = len(orders)
		orderIDs = append(orderIDs, o.ID)
		orders = append(orders, o)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if len(orderIDs) > 0 {
		drows, err := a.db.Query(fmt.Sprintf(`
			SELECT d.order_id, d.id, d.route_id, d.status, d.actual_time,
			       COALESCE(s.first_name, ''), COALESCE(v.license_plate, '')
			FROM deliveries d
			LEFT JOIN routes r ON r.id = d.route_id
			LEFT JOIN staff s ON s.id = r.driver_id
			LEFT JOIN vehicles v ON v.id = r.vehicle_id
			WHERE d.order_id IN (%s)
			ORDER BY d.id
		`, joinInts(orderIDs)))
		if err != nil {
			log.Printf("query deliveries for orders: %v", err)
		} else {
			defer drows.Close()
			for drows.Next() {
				var info DeliveryInfo
				var at sql.NullTime
				var driver, plate string
				var oid int
				if err := drows.Scan(&oid, &info.ID, &info.RouteID, &info.Status, &at, &driver, &plate); err != nil {
					log.Printf("scan delivery row: %v", err)
					continue
				}
				if at.Valid {
					s := at.Time.Format("2006-01-02 15:04")
					info.ActualTime = &s
				}
				if driver != "" {
					info.DriverName = &driver
				}
				if plate != "" {
					info.VehiclePlate = &plate
				}
				if idx, ok := orderMap[oid]; ok {
					orders[idx].Deliveries = append(orders[idx].Deliveries, info)
				}
			}
			if err := drows.Err(); err != nil {
				log.Printf("iterate delivery rows: %v", err)
			}
		}
	}

	return orders, nil
}

func (a *App) CreateOrder(payload OrderCreat) (*OrderDetail, error) {
	if !a.hasPermission("manage_orders") {
		return nil, errors.New("permission denied")
	}
	if payload.PickupNodeID <= 0 || payload.DropoffNodeID <= 0 {
		return nil, errors.New("valid pickup and dropoff nodes are required")
	}
	if payload.CustomerID <= 0 {
		return nil, errors.New("valid customer is required")
	}
	if payload.TotalWeight <= 0 {
		return nil, errors.New("total weight must be positive")
	}

	// Resolve user account ID → actual customer ID
	var custID int
	var custName string
	err := a.db.QueryRow(`
		SELECT c.id, CONCAT(c.first_name, ' ', c.last_name)
		FROM customers c
		JOIN users u ON u.customer_id = c.id
		WHERE u.id = ?
	`, payload.CustomerID).Scan(&custID, &custName)
	if err != nil {
		return nil, errors.New("customer not found")
	}

	var pickupLabel, dropoffLabel string
	err = a.db.QueryRow("SELECT label FROM nodes WHERE id = ?", payload.PickupNodeID).Scan(&pickupLabel)
	if err != nil {
		return nil, errors.New("pickup node not found")
	}
	err = a.db.QueryRow("SELECT label FROM nodes WHERE id = ?", payload.DropoffNodeID).Scan(&dropoffLabel)
	if err != nil {
		return nil, errors.New("dropoff node not found")
	}

	result, err := a.db.Exec(
		"INSERT INTO orders (customer_id, pickup_node_id, dropoff_node_id, total_weight, status) VALUES (?, ?, ?, ?, 'Draft')",
		custID, payload.PickupNodeID, payload.DropoffNodeID, payload.TotalWeight,
	)
	if err != nil {
		return nil, fmt.Errorf("create order: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("get order id: %w", err)
	}

	return &OrderDetail{
		ID:               int(id),
		CustomerID:       custID,
		CustomerName:     custName,
		PickupNodeID:     payload.PickupNodeID,
		PickupNodeLabel:  pickupLabel,
		DropoffNodeID:    payload.DropoffNodeID,
		DropoffNodeLabel: dropoffLabel,
		TotalWeight:      payload.TotalWeight,
		Status:           "Draft",
		Deliveries:       []DeliveryInfo{},
	}, nil
}

func (a *App) UpdateOrder(payload OrderUpdate) error {
	if !a.hasPermission("manage_orders") {
		return errors.New("permission denied")
	}
	if payload.PickupNodeID <= 0 || payload.DropoffNodeID <= 0 {
		return errors.New("valid pickup and dropoff nodes are required")
	}
	if payload.TotalWeight <= 0 {
		return errors.New("total weight must be positive")
	}
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM orders WHERE id = ?)", payload.ID).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check order: %w", err)
	}
	if !exists {
		return errors.New("order not found")
	}
	_, err = a.db.Exec(
		"UPDATE orders SET pickup_node_id = ?, dropoff_node_id = ?, total_weight = ? WHERE id = ?",
		payload.PickupNodeID, payload.DropoffNodeID, payload.TotalWeight, payload.ID,
	)
	if err != nil {
		return fmt.Errorf("update order: %w", err)
	}
	return nil
}

func (a *App) UpdateOrderStatus(id int, status string) error {
	if !a.hasPermission("update_order_status") {
		return errors.New("permission denied")
	}
	if !validOrderStatuses[status] {
		return fmt.Errorf("invalid status %q", status)
	}
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM orders WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check order: %w", err)
	}
	if !exists {
		return errors.New("order not found")
	}

	// Check if order has a delivery
	var deliveryID int
	err = a.db.QueryRow("SELECT COALESCE(MIN(id), 0) FROM deliveries WHERE order_id = ?", id).Scan(&deliveryID)
	if err != nil {
		return fmt.Errorf("check delivery: %w", err)
	}

	if deliveryID > 0 {
		switch status {
		case "Draft", "Pending":
			return fmt.Errorf("cannot revert dispatched order back to %s — cancel it instead", status)
		case "Cancelled":
			// Cascade: cancel delivery and free vehicle
			err = a.cancelDelivery(deliveryID)
			if err != nil {
				return fmt.Errorf("cancel delivery: %w", err)
			}
		case "Delivered":
			_, err = a.db.Exec("UPDATE deliveries SET status = 'Delivered', actual_time = NOW() WHERE id = ?", deliveryID)
			if err != nil {
				return fmt.Errorf("sync delivery: %w", err)
			}
		case "Failed":
			_, err = a.db.Exec("UPDATE deliveries SET status = 'Failed', actual_time = NOW() WHERE id = ?", deliveryID)
			if err != nil {
				return fmt.Errorf("sync delivery: %w", err)
			}
		}
	}

	_, err = a.db.Exec("UPDATE orders SET status = ? WHERE id = ?", status, id)
	if err != nil {
		return fmt.Errorf("update status: %w", err)
	}
	return nil
}

func (a *App) cancelDelivery(deliveryID int) error {
	var routeID, vehicleID int
	err := a.db.QueryRow(`
		SELECT d.route_id, COALESCE(r.vehicle_id, 0)
		FROM deliveries d
		JOIN routes r ON r.id = d.route_id
		WHERE d.id = ?
	`, deliveryID).Scan(&routeID, &vehicleID)
	if err != nil {
		return fmt.Errorf("query delivery route: %w", err)
	}

	_, err = a.db.Exec("UPDATE deliveries SET status = 'Failed', actual_time = NOW() WHERE id = ?", deliveryID)
	if err != nil {
		return fmt.Errorf("update delivery: %w", err)
	}

	if vehicleID > 0 {
		_, err = a.db.Exec("UPDATE vehicles SET current_status = 'Available' WHERE id = ?", vehicleID)
		if err != nil {
			return fmt.Errorf("free vehicle: %w", err)
		}
	}

	_, err = a.db.Exec("UPDATE routes SET status = 'Cancelled' WHERE id = ?", routeID)
	if err != nil {
		return fmt.Errorf("cancel route: %w", err)
	}
	return nil
}

func (a *App) DeleteOrder(id int) error {
	if !a.hasPermission("manage_orders") {
		return errors.New("permission denied")
	}
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM orders WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check order: %w", err)
	}
	if !exists {
		return errors.New("order not found")
	}
	var deliveryCount int
	err = a.db.QueryRow("SELECT COUNT(*) FROM deliveries WHERE order_id = ?", id).Scan(&deliveryCount)
	if err != nil {
		return fmt.Errorf("check deliveries: %w", err)
	}
	if deliveryCount > 0 {
		return fmt.Errorf("cannot delete: order has %d delivery record(s). Remove them first", deliveryCount)
	}
	_, err = a.db.Exec("DELETE FROM orders WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete order: %w", err)
	}
	return nil
}

func (a *App) UpdateDeliveryStatus(id int, status string) error {
	if !a.hasPermission("update_delivery_status") {
		return errors.New("permission denied")
	}
	if !validDeliveryStatuses[status] {
		return fmt.Errorf("invalid delivery status %q", status)
	}

	// Only verify driver assignment for Driver role; admin/manager/dispatcher can update any delivery
	if a.currentUser.RoleName == "Driver" && a.currentUser.StaffID != nil {
		var driverID int
		err := a.db.QueryRow(`
			SELECT COALESCE(r.driver_id, 0)
			FROM deliveries d
			JOIN routes r ON r.id = d.route_id
			WHERE d.id = ?
		`, id).Scan(&driverID)
		if err != nil {
			return fmt.Errorf("check route: %w", err)
		}
		if driverID != *a.currentUser.StaffID {
			return errors.New("permission denied: you are not assigned to this delivery's route")
		}
	}

	var orderID int
	err := a.db.QueryRow("SELECT d.order_id FROM deliveries d WHERE d.id = ?", id).Scan(&orderID)
	if err != nil {
		return fmt.Errorf("check delivery: %w", err)
	}

	if status == "Delivered" || status == "Failed" {
		_, err = a.db.Exec("UPDATE deliveries SET status = ?, actual_time = NOW() WHERE id = ?", status, id)
	} else {
		_, err = a.db.Exec("UPDATE deliveries SET status = ? WHERE id = ?", status, id)
	}
	if err != nil {
		return fmt.Errorf("update delivery: %w", err)
	}

	// Sync order status to match delivery outcome
	if status == "Delivered" || status == "Failed" {
		_, err = a.db.Exec("UPDATE orders SET status = ? WHERE id = ?", status, orderID)
		if err != nil {
			return fmt.Errorf("sync order status: %w", err)
		}
	}
	return nil
}

func (a *App) DeleteDelivery(id int) error {
	if !a.hasPermission("manage_deliveries") {
		return errors.New("permission denied")
	}

	// Fetch route and vehicle info before deleting
	var routeID, vehicleID int
	err := a.db.QueryRow(`
		SELECT COALESCE(d.route_id, 0), COALESCE(r.vehicle_id, 0)
		FROM deliveries d
		LEFT JOIN routes r ON r.id = d.route_id
		WHERE d.id = ?
	`, id).Scan(&routeID, &vehicleID)
	if err != nil {
		return fmt.Errorf("check delivery: %w", err)
	}
	if routeID == 0 {
		return errors.New("delivery not found")
	}

	tx, err := a.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	_, err = tx.Exec("DELETE FROM deliveries WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete delivery: %w", err)
	}

	// Reset vehicle status back to Available
	if vehicleID > 0 {
		_, err = tx.Exec("UPDATE vehicles SET current_status = 'Available' WHERE id = ?", vehicleID)
		if err != nil {
			return fmt.Errorf("reset vehicle status: %w", err)
		}
	}

	// Reset route status to Cancelled
	if routeID > 0 {
		_, err = tx.Exec("UPDATE routes SET status = 'Cancelled' WHERE id = ?", routeID)
		if err != nil {
			return fmt.Errorf("cancel route: %w", err)
		}
	}

	return tx.Commit()
}

func (a *App) GetDrivers() ([]StaffInfo, error) {
	if !a.hasPermission("manage_deliveries") {
		return nil, errors.New("permission denied")
	}
	rows, err := a.db.Query(`
		SELECT s.id, s.first_name, s.last_name
		FROM staff s
		JOIN users u ON u.staff_id = s.id
		JOIN roles r ON r.id = u.role_id
		WHERE r.role_name = 'Driver'
		ORDER BY s.first_name
	`)
	if err != nil {
		return nil, fmt.Errorf("query drivers: %w", err)
	}
	defer rows.Close()

	var drivers []StaffInfo
	for rows.Next() {
		var d StaffInfo
		if err := rows.Scan(&d.ID, &d.FirstName, &d.LastName); err != nil {
			return nil, err
		}
		drivers = append(drivers, d)
	}
	return drivers, rows.Err()
}

func (a *App) DispatchOrder(orderID int, driverID int, vehicleID int) error {
	if !a.hasPermission("manage_deliveries") {
		return errors.New("permission denied")
	}

	// Verify order exists and has no delivery yet
	var orderExists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM orders WHERE id = ?)", orderID).Scan(&orderExists)
	if err != nil {
		return fmt.Errorf("check order: %w", err)
	}
	if !orderExists {
		return errors.New("order not found")
	}

	var deliveryExists bool
	err = a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM deliveries WHERE order_id = ?)", orderID).Scan(&deliveryExists)
	if err != nil {
		return fmt.Errorf("check delivery: %w", err)
	}
	if deliveryExists {
		return errors.New("order already has a delivery assigned")
	}

	// Verify driver exists and has Driver role
	var driverExists bool
	err = a.db.QueryRow(`
		SELECT EXISTS(
			SELECT 1 FROM staff s
			JOIN users u ON u.staff_id = s.id
			JOIN roles r ON r.id = u.role_id
			WHERE s.id = ? AND r.role_name = 'Driver'
		)
	`, driverID).Scan(&driverExists)
	if err != nil {
		return fmt.Errorf("check driver: %w", err)
	}
	if !driverExists {
		return errors.New("driver not found or does not have Driver role")
	}

	// Verify driver isn't already on an active route
	var driverBusy bool
	err = a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM routes WHERE driver_id = ? AND status IN ('Planned', 'Active'))", driverID).Scan(&driverBusy)
	if err != nil {
		return fmt.Errorf("check driver route: %w", err)
	}
	if driverBusy {
		return errors.New("driver is already assigned to an active route")
	}

	// Verify vehicle exists and is available
	var vehicleStatus string
	var maxCapacity float64
	err = a.db.QueryRow("SELECT v.current_status, vt.max_weight_capacity FROM vehicles v JOIN vehicle_types vt ON vt.id = v.type_id WHERE v.id = ?", vehicleID).Scan(&vehicleStatus, &maxCapacity)
	if err != nil {
		return errors.New("vehicle not found")
	}
	if vehicleStatus != "Available" {
		return fmt.Errorf("vehicle is %s, must be Available", vehicleStatus)
	}

	// Verify order weight fits vehicle capacity
	var orderWeight float64
	var pickupNodeID, dropoffNodeID int
	err = a.db.QueryRow("SELECT total_weight, pickup_node_id, dropoff_node_id FROM orders WHERE id = ?", orderID).Scan(&orderWeight, &pickupNodeID, &dropoffNodeID)
	if err != nil {
		return fmt.Errorf("check order: %w", err)
	}
	if orderWeight > maxCapacity {
		return fmt.Errorf("order weight (%.2f kg) exceeds vehicle capacity (%.2f kg)", orderWeight, maxCapacity)
	}

	// Compute fastest path
	edgeIDs, totalDist, _, err := a.dijkstraFastestPath(pickupNodeID, dropoffNodeID)
	if err != nil {
		return fmt.Errorf("route computation: %w", err)
	}

	tx, err := a.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	result, err := tx.Exec(
		"INSERT INTO routes (driver_id, vehicle_id, planned_date, total_distance, status) VALUES (?, ?, CURDATE(), ?, 'Planned')",
		driverID, vehicleID, totalDist,
	)
	if err != nil {
		return fmt.Errorf("create route: %w", err)
	}
	routeID, err := result.LastInsertId()
	if err != nil {
		return fmt.Errorf("get route id: %w", err)
	}

	// Insert route segments
	for i, eid := range edgeIDs {
		_, err = tx.Exec(
			"INSERT INTO route_segments (route_id, edge_id, sequence_order) VALUES (?, ?, ?)",
			routeID, eid, i+1,
		)
		if err != nil {
			return fmt.Errorf("insert route segment %d: %w", i, err)
		}
	}

	_, err = tx.Exec(
		"INSERT INTO deliveries (order_id, route_id, status) VALUES (?, ?, 'Pending')",
		orderID, routeID,
	)
	if err != nil {
		return fmt.Errorf("create delivery: %w", err)
	}

	// Sync order status to In Transit
	_, err = tx.Exec("UPDATE orders SET status = 'In Transit' WHERE id = ?", orderID)
	if err != nil {
		return fmt.Errorf("update order status: %w", err)
	}

	// Update vehicle status to On Route
	_, err = tx.Exec("UPDATE vehicles SET current_status = 'On Route' WHERE id = ?", vehicleID)
	if err != nil {
		return fmt.Errorf("update vehicle: %w", err)
	}

	return tx.Commit()
}
