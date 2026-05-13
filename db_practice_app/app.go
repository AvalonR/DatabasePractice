package main

import (
	"context"
	"database/sql"
	"db_practice_app/db"
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

func (a *App) Auth(username string, password string) bool {
	var dbPassword string

	err := a.db.QueryRow("SELECT password_hash FROM users WHERE username = ?", username).Scan(&dbPassword)
	if err != nil {
		fmt.Println(err)
		return false
	}

	if dbPassword == password {
		return true
	}

	return false
}

func (a *App) GetNetworkData() (db.NetworkData, error) {
	var networkData db.NetworkData

	nodeRows, err := a.db.Query("SELECT id, x_coord, y_coord, label FROM nodes")
	if err != nil {
		return networkData, err
	}
	defer nodeRows.Close()

	for nodeRows.Next() {
		var node db.Node
		err := nodeRows.Scan(&node.ID, &node.XCoord, &node.YCoord, &node.Label)
		if err != nil {
			return networkData, err
		}
		networkData.Nodes = append(networkData.Nodes, node)
	}

	edgeRows, err := a.db.Query("SELECT id, node_a_id, node_b_id, distance_units, speed_limit FROM edges")
	if err != nil {
		return networkData, err
	}
	defer edgeRows.Close()

	for edgeRows.Next() {
		var edge db.Edge
		err := edgeRows.Scan(&edge.ID, &edge.NodeAId, &edge.NodeBId, &edge.DistanceUnits, &edge.SpeedLimit)
		if err != nil {
			return networkData, err
		}
		networkData.Edges = append(networkData.Edges, edge)
	}

	return networkData, nil
}

func (a *App) GetNodeStats(nodeID int) (int, error) {
	var count int
	err := a.db.QueryRow("SELECT COUNT(*) FROM orders WHERE pickup_node_id = ?", nodeID).Scan(&count)
	if err != nil {
		return count, err
	}

	return count, err

}
