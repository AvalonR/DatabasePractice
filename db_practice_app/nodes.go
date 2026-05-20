package main

import (
	"database/sql"
	"db_practice_app/db"
	"errors"
	"fmt"
	"strings"
	"time"
)

type OrderInfo struct {
	ID                 int     `json:"id"`
	Status             string  `json:"status"`
	Weight             float64 `json:"weight"`
	OrderDate          string  `json:"order_date"`
	CustomerID         int     `json:"customer_id"`
	CustomerName       string  `json:"customer_name"`
	PickupNodeLabel    string  `json:"pickup_node_label"`
	DropoffNodeLabel   string  `json:"dropoff_node_label"`
	DriverName         string  `json:"driver_name,omitempty"`
	VehiclePlate       string  `json:"vehicle_plate,omitempty"`
	ActualDeliveryTime string  `json:"actual_delivery_time,omitempty"`
	Revenue            float64 `json:"revenue,omitempty"`
	CustomerEmail      string  `json:"customer_email,omitempty"`
	CustomerPhone      string  `json:"customer_phone,omitempty"`
}

type NodeDetail struct {
	NodeID          int         `json:"node_id"`
	PendingOrders   []OrderInfo `json:"pending_orders"`
	CompletedOrders []OrderInfo `json:"completed_orders"`
	TotalRevenue    float64     `json:"total_revenue"`
}

func (a *App) GetNetworkData() (db.NetworkData, error) {
	var networkData db.NetworkData

	nodeRows, err := a.db.Query("SELECT id, x_coord, y_coord, label FROM nodes")
	if err != nil {
		println(err.Error())
		return networkData, err
	}
	defer nodeRows.Close()

	for nodeRows.Next() {
		var node db.Node
		err := nodeRows.Scan(&node.ID, &node.XCoord, &node.YCoord, &node.Label)
		if err != nil {
			return networkData, fmt.Errorf("scan node: %w", err)
		}
		networkData.Nodes = append(networkData.Nodes, node)
	}
	if err := nodeRows.Err(); err != nil {
		return networkData, fmt.Errorf("iterate nodes: %w", err)
	}

	edgeRows, err := a.db.Query("SELECT id, node_a_id, node_b_id, distance_units, speed_limit FROM edges")
	if err != nil {
		return networkData, fmt.Errorf("query edges: %w", err)
	}
	defer edgeRows.Close()

	for edgeRows.Next() {
		var edge db.Edge
		err := edgeRows.Scan(&edge.ID, &edge.NodeAId, &edge.NodeBId, &edge.DistanceUnits, &edge.SpeedLimit)
		if err != nil {
			return networkData, fmt.Errorf("scan edge: %w", err)
		}
		networkData.Edges = append(networkData.Edges, edge)
	}
	if err := edgeRows.Err(); err != nil {
		return networkData, fmt.Errorf("iterate edges: %w", err)
	}

	return networkData, nil
}

func (a *App) GetNodeDetails(nodeID int) (*NodeDetail, error) {
	detail := &NodeDetail{
		NodeID: nodeID,
	}

	canViewFinancials := a.hasPermission("view_financials")
	canViewContact := a.hasPermission("view_customer_info")
	canViewAll := a.hasPermission("view_all_orders")

	var visibilityFilter string
	var visArgs []interface{}
	if !canViewAll && a.currentUser != nil {
		if a.currentUser.StaffID != nil {
			visibilityFilter = "AND EXISTS (SELECT 1 FROM deliveries d2 JOIN routes r2 ON r2.id = d2.route_id AND r2.driver_id = ? WHERE d2.order_id = o.id)"
			visArgs = append(visArgs, *a.currentUser.StaffID)
		} else if a.currentUser.CustomerID != nil {
			visibilityFilter = "AND o.customer_id = ?"
			visArgs = append(visArgs, *a.currentUser.CustomerID)
		} else {
			visibilityFilter = "AND 1=0"
		}
	}

	const orderQuery = `
		SELECT
			o.id, o.status, o.total_weight, o.order_date, o.customer_id,
			COALESCE(CONCAT(c.first_name, ' ', c.last_name), '') AS customer_name,
			COALESCE(pn.label, '') AS pickup_label,
			COALESCE(dn.label, '') AS dropoff_label,
			COALESCE(s.first_name, '') AS driver_first,
			COALESCE(s.last_name, '') AS driver_last,
			COALESCE(v.license_plate, '') AS vehicle_plate,
			d.actual_time,
			COALESCE(c.email, '') AS customer_email,
			COALESCE(c.phone, '') AS customer_phone,
			COALESCE(vt.price_per_kg, 10.0) AS price_per_kg
		FROM orders o
		JOIN customers c ON c.id = o.customer_id
		JOIN nodes pn ON pn.id = o.pickup_node_id
		JOIN nodes dn ON dn.id = o.dropoff_node_id
		LEFT JOIN deliveries d ON d.order_id = o.id
		LEFT JOIN routes r ON r.id = d.route_id
		LEFT JOIN staff s ON s.id = r.driver_id
		LEFT JOIN vehicles v ON v.id = r.vehicle_id
		LEFT JOIN vehicle_types vt ON vt.id = v.type_id
		WHERE (o.pickup_node_id = ? OR o.dropoff_node_id = ?)
		%s`

	scanOrder := func(rows *sql.Rows) (OrderInfo, error) {
		var o OrderInfo
		var driverFirst, driverLast, vehiclePlate, email, phone string
		var actualTime sql.NullTime
		var pricePerKg float64
		err := rows.Scan(
			&o.ID, &o.Status, &o.Weight, &o.OrderDate, &o.CustomerID,
			&o.CustomerName, &o.PickupNodeLabel, &o.DropoffNodeLabel,
			&driverFirst, &driverLast, &vehiclePlate,
			&actualTime, &email, &phone,
			&pricePerKg,
		)
		if err != nil {
			return o, err
		}
		if driverFirst != "" || driverLast != "" {
			o.DriverName = strings.TrimSpace(driverFirst + " " + driverLast)
		}
		if vehiclePlate != "" {
			o.VehiclePlate = vehiclePlate
		}
		if actualTime.Valid {
			o.ActualDeliveryTime = actualTime.Time.Format(time.RFC3339)
		}
		o.Revenue = o.Weight * pricePerKg
		if !canViewFinancials {
			o.Revenue = 0
		}
		if canViewContact {
			o.CustomerEmail = email
			o.CustomerPhone = phone
		}
		return o, nil
	}

	pendingQuery := fmt.Sprintf(orderQuery+` AND o.status IN ('Pending', 'In Transit')`, visibilityFilter)
	pendingArgs := []interface{}{nodeID, nodeID}
	pendingArgs = append(pendingArgs, visArgs...)
	rows, err := a.db.Query(pendingQuery, pendingArgs...)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}
	defer rows.Close()

	var totalRevenue float64
	for rows.Next() {
		o, err := scanOrder(rows)
		if err != nil {
			fmt.Println(err)
			return nil, err
		}
		detail.PendingOrders = append(detail.PendingOrders, o)
		totalRevenue += o.Revenue
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	completedQuery := fmt.Sprintf(orderQuery+` AND o.status = 'Delivered'`, visibilityFilter)
	completedArgs := []interface{}{nodeID, nodeID}
	completedArgs = append(completedArgs, visArgs...)
	cRows, err := a.db.Query(completedQuery, completedArgs...)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}
	defer cRows.Close()

	for cRows.Next() {
		o, err := scanOrder(cRows)
		if err != nil {
			fmt.Println(err)
			return nil, err
		}
		detail.CompletedOrders = append(detail.CompletedOrders, o)
		totalRevenue += o.Revenue
	}
	if err := cRows.Err(); err != nil {
		return nil, err
	}

	if canViewFinancials {
		detail.TotalRevenue = totalRevenue
	}

	return detail, nil
}

func (a *App) GetNodeStats(nodeID int) (int, error) {
	var count int
	err := a.db.QueryRow("SELECT COUNT(*) FROM orders WHERE pickup_node_id = ? OR dropoff_node_id = ?", nodeID, nodeID).Scan(&count)
	if err != nil {
		return count, err
	}

	return count, nil

}

// Node CRUD

func (a *App) CreateNode(xCoord float64, yCoord float64, label string) (*db.Node, error) {
	if !a.hasPermission("manage_nodes") {
		return nil, errors.New("permission denied")
	}
	if label == "" {
		return nil, errors.New("label is required")
	}
	result, err := a.db.Exec("INSERT INTO nodes (x_coord, y_coord, label) VALUES (?, ?, ?)", xCoord, yCoord, label)
	if err != nil {
		return nil, fmt.Errorf("create node: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return nil, err
	}
	return &db.Node{ID: int(id), XCoord: xCoord, YCoord: yCoord, Label: label}, nil
}

func (a *App) UpdateNode(id int, xCoord float64, yCoord float64, label string) error {
	if !a.hasPermission("manage_nodes") {
		return errors.New("permission denied")
	}
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM nodes WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check node: %w", err)
	}
	if !exists {
		return errors.New("node not found")
	}
	_, err = a.db.Exec("UPDATE nodes SET x_coord = ?, y_coord = ?, label = ? WHERE id = ?", xCoord, yCoord, label, id)
	if err != nil {
		return fmt.Errorf("update node: %w", err)
	}
	return nil
}

func (a *App) DeleteNode(id int) error {
	if !a.hasPermission("manage_nodes") {
		return errors.New("permission denied")
	}

	var edgeCount int
	err := a.db.QueryRow("SELECT COUNT(*) FROM edges WHERE node_a_id = ? OR node_b_id = ?", id, id).Scan(&edgeCount)
	if err != nil {
		return fmt.Errorf("check edges: %w", err)
	}
	if edgeCount > 0 {
		return errors.New("cannot delete: node is connected to existing edges. Remove edge connections first")
	}

	var orderCount int
	err = a.db.QueryRow("SELECT COUNT(*) FROM orders WHERE (pickup_node_id = ? OR dropoff_node_id = ?) AND status IN ('Pending', 'In Transit')", id, id).Scan(&orderCount)
	if err != nil {
		return fmt.Errorf("check orders: %w", err)
	}
	if orderCount > 0 {
		return errors.New("cannot delete: node has active orders. Resolve them first")
	}

	_, err = a.db.Exec("DELETE FROM nodes WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete node: %w", err)
	}
	return nil
}

func (a *App) CreateEdge(nodeAId int, nodeBId int, distanceUnits float64, speedLimit int) (*db.Edge, error) {
	if !a.hasPermission("manage_edges") {
		return nil, errors.New("permission denied")
	}
	if nodeAId == nodeBId {
		return nil, errors.New("cannot create edge between the same node")
	}
	if distanceUnits <= 0 {
		return nil, errors.New("distance must be positive")
	}
	if speedLimit <= 0 {
		return nil, errors.New("speed limit must be positive")
	}
	result, err := a.db.Exec("INSERT INTO edges (node_a_id, node_b_id, distance_units, speed_limit) VALUES (?, ?, ?, ?)", nodeAId, nodeBId, distanceUnits, speedLimit)
	if err != nil {
		return nil, fmt.Errorf("create edge: %w", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		return nil, err
	}
	return &db.Edge{ID: int(id), NodeAId: nodeAId, NodeBId: nodeBId, DistanceUnits: distanceUnits, SpeedLimit: speedLimit}, nil
}

func (a *App) UpdateEdge(id int, nodeAId int, nodeBId int, distanceUnits float64, speedLimit int) error {
	if !a.hasPermission("manage_edges") {
		return errors.New("permission denied")
	}
	if nodeAId == nodeBId {
		return errors.New("cannot set edge between the same node")
	}
	if distanceUnits <= 0 {
		return errors.New("distance must be positive")
	}
	if speedLimit <= 0 {
		return errors.New("speed limit must be positive")
	}
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM edges WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check edge: %w", err)
	}
	if !exists {
		return errors.New("edge not found")
	}
	_, err = a.db.Exec("UPDATE edges SET node_a_id = ?, node_b_id = ?, distance_units = ?, speed_limit = ? WHERE id = ?", nodeAId, nodeBId, distanceUnits, speedLimit, id)
	if err != nil {
		return fmt.Errorf("update edge: %w", err)
	}
	return nil
}

func (a *App) DeleteEdge(id int) error {
	if !a.hasPermission("manage_edges") {
		return errors.New("permission denied")
	}

	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM edges WHERE id = ?)", id).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check edge: %w", err)
	}
	if !exists {
		return errors.New("edge not found")
	}

	_, err = a.db.Exec("DELETE FROM edges WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete edge: %w", err)
	}
	return nil
}
