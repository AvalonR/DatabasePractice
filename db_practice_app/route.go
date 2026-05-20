package main

import (
	"errors"
	"fmt"
	"math"
)

type RouteEdgeDetail struct {
	SequenceOrder int     `json:"sequence_order"`
	EdgeID        int     `json:"edge_id"`
	NodeAID       int     `json:"node_a_id"`
	NodeBID       int     `json:"node_b_id"`
	NodeAX        float64 `json:"node_a_x"`
	NodeAY        float64 `json:"node_a_y"`
	NodeBX        float64 `json:"node_b_x"`
	NodeBY        float64 `json:"node_b_y"`
	DistanceUnits float64 `json:"distance_units"`
}

type DeliveryRoute struct {
	DeliveryID    int               `json:"delivery_id"`
	DriverName    string            `json:"driver_name"`
	VehiclePlate  string            `json:"vehicle_plate"`
	TotalDistance float64           `json:"total_distance"`
	TotalTime     float64           `json:"total_time"`
	PickupNodeID  int               `json:"pickup_node_id"`
	DropoffNodeID int               `json:"dropoff_node_id"`
	Segments      []RouteEdgeDetail `json:"segments"`
}

type edgeInfo struct {
	neighbor int
	edgeID   int
	distance float64
	speed    int
}

func (a *App) dijkstraFastestPath(fromNodeID, toNodeID int) ([]int, float64, float64, error) {
	if fromNodeID == toNodeID {
		return []int{}, 0, 0, nil
	}

	rows, err := a.db.Query("SELECT id, node_a_id, node_b_id, distance_units, COALESCE(speed_limit, 50) FROM edges")
	if err != nil {
		return nil, 0, 0, fmt.Errorf("query edges: %w", err)
	}
	defer rows.Close()

	adj := map[int][]edgeInfo{}
	for rows.Next() {
		var id, nodeA, nodeB, speed int
		var dist float64
		if err := rows.Scan(&id, &nodeA, &nodeB, &dist, &speed); err != nil {
			return nil, 0, 0, fmt.Errorf("scan edge: %w", err)
		}
		if speed <= 0 {
			speed = 50
		}
		adj[nodeA] = append(adj[nodeA], edgeInfo{nodeB, id, dist, speed})
		adj[nodeB] = append(adj[nodeB], edgeInfo{nodeA, id, dist, speed})
	}
	if err := rows.Err(); err != nil {
		return nil, 0, 0, err
	}

	if _, ok := adj[fromNodeID]; !ok {
		return nil, 0, 0, errors.New("pickup node has no connecting edges")
	}
	if _, ok := adj[toNodeID]; !ok {
		return nil, 0, 0, errors.New("dropoff node has no connecting edges")
	}

	type state struct {
		time     float64
		distance float64
		prevNode int
		prevEdge int
	}

	states := map[int]*state{}
	for node := range adj {
		states[node] = &state{time: math.Inf(1), prevNode: -1}
	}
	states[fromNodeID].time = 0

	visited := map[int]bool{}

	for {
		u := -1
		minTime := math.Inf(1)
		for node, s := range states {
			if !visited[node] && s.time < minTime {
				minTime = s.time
				u = node
			}
		}
		if u == -1 || u == toNodeID {
			break
		}
		visited[u] = true

		for _, edge := range adj[u] {
			if visited[edge.neighbor] {
				continue
			}
			weight := edge.distance / float64(edge.speed)
			alt := states[u].time + weight
			if alt < states[edge.neighbor].time {
				states[edge.neighbor].time = alt
				states[edge.neighbor].distance = states[u].distance + edge.distance
				states[edge.neighbor].prevNode = u
				states[edge.neighbor].prevEdge = edge.edgeID
			}
		}
	}

	dest, ok := states[toNodeID]
	if !ok || math.IsInf(dest.time, 1) {
		return nil, 0, 0, errors.New("no route exists between pickup and dropoff nodes")
	}

	var edgeIDs []int
	cur := toNodeID
	for cur != fromNodeID {
		s := states[cur]
		if s.prevEdge == 0 || s.prevNode < 0 {
			return nil, 0, 0, errors.New("route reconstruction failed")
		}
		edgeIDs = append(edgeIDs, s.prevEdge)
		cur = s.prevNode
	}

	for i, j := 0, len(edgeIDs)-1; i < j; i, j = i+1, j-1 {
		edgeIDs[i], edgeIDs[j] = edgeIDs[j], edgeIDs[i]
	}

	return edgeIDs, dest.distance, dest.time, nil
}

func (a *App) GetDeliveryRoutePath(deliveryID int) (*DeliveryRoute, error) {
	if !a.hasPermission("view_all_orders") && !a.hasPermission("view_personal_orders") {
		return nil, errors.New("permission denied")
	}

	var routeID int
	result := &DeliveryRoute{DeliveryID: deliveryID}

	err := a.db.QueryRow(`
		SELECT d.route_id,
		       COALESCE(CONCAT(s.first_name, ' ', s.last_name), ''),
		       COALESCE(v.license_plate, ''),
		       o.pickup_node_id, o.dropoff_node_id
		FROM deliveries d
		JOIN routes r ON r.id = d.route_id
		LEFT JOIN staff s ON s.id = r.driver_id
		LEFT JOIN vehicles v ON v.id = r.vehicle_id
		JOIN orders o ON o.id = d.order_id
		WHERE d.id = ?
	`, deliveryID).Scan(&routeID, &result.DriverName, &result.VehiclePlate, &result.PickupNodeID, &result.DropoffNodeID)
	if err != nil {
		return nil, fmt.Errorf("query delivery: %w", err)
	}

	segRows, err := a.db.Query(`
		SELECT rs.sequence_order, e.id, e.node_a_id, e.node_b_id,
		       e.distance_units, COALESCE(e.speed_limit, 50),
		       na.x_coord, na.y_coord, nb.x_coord, nb.y_coord
		FROM route_segments rs
		JOIN edges e ON e.id = rs.edge_id
		JOIN nodes na ON na.id = e.node_a_id
		JOIN nodes nb ON nb.id = e.node_b_id
		WHERE rs.route_id = ?
		ORDER BY rs.sequence_order
	`, routeID)
	if err != nil {
		return nil, fmt.Errorf("query route segments: %w", err)
	}
	defer segRows.Close()

	for segRows.Next() {
		var seg RouteEdgeDetail
		var speed int
		if err := segRows.Scan(&seg.SequenceOrder, &seg.EdgeID,
			&seg.NodeAID, &seg.NodeBID, &seg.DistanceUnits,
			&speed, &seg.NodeAX, &seg.NodeAY, &seg.NodeBX, &seg.NodeBY); err != nil {
			return nil, fmt.Errorf("scan route segment: %w", err)
		}
		if speed <= 0 {
			speed = 50
		}
		result.TotalDistance += seg.DistanceUnits
		result.TotalTime += seg.DistanceUnits / float64(speed)
		result.Segments = append(result.Segments, seg)
	}
	if err := segRows.Err(); err != nil {
		return nil, err
	}

	if result.Segments == nil {
		result.Segments = []RouteEdgeDetail{}
	}
	return result, nil
}

func (a *App) GetOrderRouteEdgeIds(orderID int) ([]int, error) {
	if !a.hasPermission("view_all_orders") && !a.hasPermission("view_personal_orders") {
		return nil, errors.New("permission denied")
	}
	var edgeIDs []int
	rows, err := a.db.Query(`
        SELECT DISTINCT rs.edge_id
        FROM deliveries d
        JOIN routes r ON r.id = d.route_id
        JOIN route_segments rs ON rs.route_id = r.id
        WHERE d.order_id = ?
        ORDER BY rs.sequence_order
    `, orderID)
	if err != nil {
		return nil, fmt.Errorf("query deliveries: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var edgeID int
		if err := rows.Scan(&edgeID); err != nil {
			return nil, fmt.Errorf("scan delivery: %w", err)
		}
		edgeIDs = append(edgeIDs, edgeID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return edgeIDs, nil
}
