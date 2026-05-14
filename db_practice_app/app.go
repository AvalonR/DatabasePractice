package main

import (
	"context"
	"database/sql"
	"db_practice_app/db"
	"errors"
	"fmt"
	"log"
)

// App struct
type App struct {
	ctx context.Context
	db  *sql.DB
}

func NewApp() *App {
	return &App{}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	database, err := db.InitDB()
	if err != nil {
		log.Fatal(err)
	}
	a.db = database
}

// User type
type AuthenticatedUser struct {
	ID          int      `json:"id"`
	Username    string   `json:"username"`
	RoleName    string   `json:"role_name"`
	Permissions []string `json:"permissions"`
}

func (a *App) Auth(username string, password string) (*AuthenticatedUser, error) {
	var user db.User

	err := a.db.QueryRow("SELECT id, username, password_hash, role_id FROM users WHERE username = ?", username).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.RoleID)
	if err != nil {
		fmt.Println(err)
		return nil, errors.New("User not found")
	}

	if user.PasswordHash != password {
		return nil, errors.New("Invalid username or password")
	}

	var roleName string
	err = a.db.QueryRow("SELECT role_name FROM roles WHERE id = ?", user.RoleID).Scan(&roleName)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}

	rows, err := a.db.Query("SELECT p.perm_key FROM permissions p JOIN role_permissions rp ON p.id = rp.permission_id WHERE rp.role_id = ?", user.RoleID)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}
	defer rows.Close()

	var permissions []string
	for rows.Next() {
		var permKey string
		err := rows.Scan(&permKey)
		if err != nil {
			fmt.Println(err)
			return nil, err
		}
		permissions = append(permissions, permKey)
	}

	return &AuthenticatedUser{
		ID:          user.ID,
		Username:    user.Username,
		RoleName:    roleName,
		Permissions: permissions,
	}, nil
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
			println(err.Error())
			return networkData, err
		}
		networkData.Nodes = append(networkData.Nodes, node)
	}

	edgeRows, err := a.db.Query("SELECT id, node_a_id, node_b_id, distance_units, speed_limit FROM edges")
	if err != nil {
		println(err.Error())
		return networkData, err
	}
	defer edgeRows.Close()

	for edgeRows.Next() {
		var edge db.Edge
		err := edgeRows.Scan(&edge.ID, &edge.NodeAId, &edge.NodeBId, &edge.DistanceUnits, &edge.SpeedLimit)
		if err != nil {
			println(err.Error())
			return networkData, err
		}
		networkData.Edges = append(networkData.Edges, edge)
	}

	return networkData, nil
}

type OrderInfo struct {
	ID         int     `json:"id"`
	Status     string  `json:"status"`
	Weight     float64 `json:"weight"`
	OrderDate  string  `json:"order_date"`
	CustomerID int     `json:"customer_id"`
}
type NodeDetail struct {
	NodeID          int         `json:"node_id"`
	PendingOrders   []OrderInfo `json:"pending_orders"`
	CompletedOrders []OrderInfo `json:"completed_orders"`
	TotalRevenue    int         `json:"total_revenue"`
}

func (a *App) GetNodeDetails(nodeID int) (*NodeDetail, error) {
	detail := &NodeDetail{
		NodeID: nodeID,
	}

	rows, err := a.db.Query("SELECT id, status, total_weight, order_date, customer_id FROM orders WHERE (pickup_node_id = ? OR dropoff_node_id = ?) AND status IN ('Pending', 'In Transit')", nodeID, nodeID)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}

	defer rows.Close()

	for rows.Next() {
		var o OrderInfo
		if err := rows.Scan(&o.ID, &o.Status, &o.Weight, &o.OrderDate, &o.CustomerID); err != nil {
			fmt.Println(err)
			return nil, err
		}
		detail.PendingOrders = append(detail.PendingOrders, o)
	}

	cRows, err := a.db.Query(`
		SELECT id, status, total_weight, order_date, customer_id FROM orders
		WHERE (pickup_node_id = ? OR dropoff_node_id = ?) 
		AND status = 'Delivered'`,
		nodeID, nodeID)

	if err != nil {
		fmt.Println(err)
		return nil, err
	}
	defer cRows.Close()
	for cRows.Next() {
		var o OrderInfo
		if err := cRows.Scan(&o.ID, &o.Status, &o.Weight, &o.OrderDate, &o.CustomerID); err != nil {
			fmt.Println(err)
			return nil, err
		}
		detail.CompletedOrders = append(detail.CompletedOrders, o)
	}

	return detail, nil
}

func (a *App) GetNodeStats(nodeID int) (int, error) {
	var count int
	err := a.db.QueryRow("SELECT COUNT(*) FROM orders WHERE pickup_node_id = ?", nodeID).Scan(&count)
	if err != nil {
		return count, err
	}

	return count, err

}
