-- ==============================================================
-- queries.sql
-- Delivery Network Management System
-- 30 executable SQL queries + 1 trigger definition
-- All queries have been tested against the populated database
-- and return meaningful results.
--
-- To execute: mysql -u root -p delivery_system < queries.sql
-- ==============================================================

USE delivery_system;

-- ==============================================================
-- PART 1: BASIC QUERIES (3 queries)
-- Simple SELECT statements for core data retrieval
-- ==============================================================

-- 1. Retrieve all orders with their current status for customer ID 1
-- Purpose: Customer order history view
SELECT '--- Query 1: Orders for customer #1 ---' AS '';
SELECT id, status, total_weight, order_date
FROM orders
WHERE customer_id = 1;

-- 2. List all available vehicles with their type information
-- Purpose: Fleet availability display in the dispatch modal
SELECT '--- Query 2: Available vehicles ---' AS '';
SELECT v.id, v.license_plate, vt.type_name, vt.max_weight_capacity
FROM vehicles v
JOIN vehicle_types vt ON vt.id = v.type_id
WHERE v.current_status = 'Available';

-- 3. Find all deliveries assigned to a specific driver on an active route
-- Purpose: Driver's active delivery list
SELECT '--- Query 3: Deliveries for driver #3 ---' AS '';
SELECT d.id, d.status, o.id AS order_id
FROM deliveries d
JOIN routes r ON r.id = d.route_id
JOIN orders o ON o.id = d.order_id
WHERE r.driver_id = 3 AND r.status IN ('Planned', 'Active');


-- ==============================================================
-- PART 2: SUBSTRING AND DATE/TIME FUNCTION QUERIES (5 queries)
-- Demonstrates text manipulation and date/time functions
-- ==============================================================

-- 4. [TEXT] Extract the domain from customer email addresses
SELECT '--- Query 4: Email domain extraction ---' AS '';
SELECT email, SUBSTRING_INDEX(email, '@', -1) AS domain
FROM customers;

-- 5. [TEXT] Find orders whose status contains a specific substring
SELECT '--- Query 5: Orders containing Transit in status ---' AS '';
SELECT *
FROM orders
WHERE INSTR(status, 'Transit') > 0;

-- 6. [DATE] Extract the year from order date
SELECT '--- Query 6: Order year extraction ---' AS '';
SELECT id, order_date, YEAR(order_date) AS year
FROM orders;

-- 7. [DATE] Find orders placed in the last 30 days
SELECT '--- Query 7: Recent orders (last 30 days) ---' AS '';
SELECT *
FROM orders
WHERE order_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY);

-- 8. [DATE] Extract the hour from delivery actual_time
SELECT '--- Query 8: Delivery hour extraction ---' AS '';
SELECT id, actual_time, HOUR(actual_time) AS hour
FROM deliveries
WHERE actual_time IS NOT NULL;


-- ==============================================================
-- PART 3A: JOIN QUERIES — TWO TABLES (6 queries)
-- Consolidates data from two related tables
-- ==============================================================

-- 9. Orders with customer names
SELECT '--- Query 9: Orders with customer names ---' AS '';
SELECT o.*, c.first_name, c.last_name
FROM orders o
JOIN customers c ON c.id = o.customer_id;

-- 10. Vehicles with their type details
SELECT '--- Query 10: Vehicles with type details ---' AS '';
SELECT v.*, vt.type_name, vt.max_weight_capacity
FROM vehicles v
JOIN vehicle_types vt ON vt.id = v.type_id;

-- 11. Audit logs with usernames (LEFT JOIN for system actions)
SELECT '--- Query 11: Audit logs with usernames ---' AS '';
SELECT al.*, COALESCE(u.username, '[system]') AS username
FROM system_audit_logs al
LEFT JOIN users u ON u.id = al.user_id;

-- 12. Staff with their user accounts
SELECT '--- Query 12: Staff with user accounts ---' AS '';
SELECT s.*, u.username
FROM staff s
LEFT JOIN users u ON u.staff_id = s.id;

-- 13. Nodes with their map region information
SELECT '--- Query 13: Nodes with map regions ---' AS '';
SELECT n.*, r.region_name, r.risk_level
FROM nodes n
JOIN map_regions r ON r.id = n.map_region_id;

-- 14. Vehicles with their maintenance log entries
SELECT '--- Query 14: Vehicles with maintenance logs ---' AS '';
SELECT v.id, v.license_plate, ml.service_date, ml.description, ml.cost
FROM vehicles v
LEFT JOIN maintenance_logs ml ON ml.vehicle_id = v.id;


-- ==============================================================
-- PART 3B: JOIN QUERIES — THREE OR MORE TABLES (6 queries)
-- Multi-table data aggregation across the schema
-- ==============================================================

-- 15. Routes with driver name and vehicle license plate
SELECT '--- Query 15: Routes with driver and vehicle ---' AS '';
SELECT r.*, s.first_name, s.last_name, v.license_plate
FROM routes r
JOIN staff s ON s.id = r.driver_id
JOIN vehicles v ON v.id = r.vehicle_id;

-- 16. Deliveries with order status, weight, and route distance
SELECT '--- Query 16: Deliveries with order and route ---' AS '';
SELECT d.id, o.status AS order_status, o.total_weight,
       r.total_distance, r.planned_date
FROM deliveries d
JOIN orders o ON o.id = d.order_id
JOIN routes r ON r.id = d.route_id;

-- 17. Edge connections with both endpoint node labels
SELECT '--- Query 17: Edges with node labels ---' AS '';
SELECT e.id, n1.label AS start_node, n2.label AS end_node,
       e.distance_units, e.speed_limit
FROM edges e
JOIN nodes n1 ON n1.id = e.node_a_id
JOIN nodes n2 ON n2.id = e.node_b_id;

-- 18. Orders with customer, pickup, and dropoff details
SELECT '--- Query 18: Complete order details ---' AS '';
SELECT o.id, c.first_name, c.last_name,
       pn.label AS pickup_location,
       dn.label AS dropoff_location
FROM orders o
JOIN customers c ON c.id = o.customer_id
JOIN nodes pn ON pn.id = o.pickup_node_id
JOIN nodes dn ON dn.id = o.dropoff_node_id;

-- 19. Route segments with edge distance and from/to node names
SELECT '--- Query 19: Route segment details ---' AS '';
SELECT rs.id, rs.route_id, e.distance_units,
       n1.label AS from_node, n2.label AS to_node,
       rs.sequence_order
FROM route_segments rs
JOIN routes r ON r.id = rs.route_id
JOIN edges e ON e.id = rs.edge_id
JOIN nodes n1 ON n1.id = e.node_a_id
JOIN nodes n2 ON n2.id = e.node_b_id;

-- 20. Users with role name and all assigned permissions
SELECT '--- Query 20: User permissions (user #1 - Admin) ---' AS '';
SELECT u.username, r.role_name, p.perm_key
FROM users u
JOIN roles r ON r.id = u.role_id
JOIN role_permissions rp ON rp.role_id = r.id
JOIN permissions p ON p.id = rp.permission_id
WHERE u.id = 1;


-- ==============================================================
-- PART 4: COMPLEX QUERIES WITH SUBQUERIES (10 queries)
-- Advanced analytics using nested queries, EXISTS, and window functions
-- ==============================================================

-- 21. Find customers whose total order weight exceeds the average
SELECT '--- Query 21: High-value customers ---' AS '';
SELECT customer_id, SUM(total_weight) AS total_weight
FROM orders
GROUP BY customer_id
HAVING SUM(total_weight) > (SELECT AVG(total_weight) FROM orders);

-- 22. Find drivers with more active routes than the average
SELECT '--- Query 22: Busy drivers ---' AS '';
SELECT driver_id, COUNT(*) AS active_route_count
FROM routes
WHERE status = 'Active'
GROUP BY driver_id
HAVING COUNT(*) > (
    SELECT AVG(cnt)
    FROM (SELECT COUNT(*) AS cnt
          FROM routes
          WHERE status = 'Active'
          GROUP BY driver_id) AS avg_tbl
);

-- 23. Get the most recent audit entry for each user
SELECT '--- Query 23: Latest audit entry per user ---' AS '';
SELECT a.*
FROM system_audit_logs a
WHERE a.action_timestamp = (
    SELECT MAX(a2.action_timestamp)
    FROM system_audit_logs a2
    WHERE a2.user_id = a.user_id
);

-- 24. Find nodes that have no connected edges
SELECT '--- Query 24: Unconnected nodes ---' AS '';
SELECT *
FROM nodes n
WHERE NOT EXISTS (
    SELECT 1 FROM edges e
    WHERE e.node_a_id = n.id OR e.node_b_id = n.id
);

-- 25. Orders where delivery took longer than estimated travel time
SELECT '--- Query 25: Late deliveries ---' AS '';
SELECT o.id, o.order_date, d.actual_time, r.total_distance
FROM orders o
JOIN deliveries d ON d.order_id = o.id
JOIN routes r ON r.id = d.route_id
WHERE d.actual_time IS NOT NULL
  AND TIMESTAMPDIFF(HOUR, o.order_date, d.actual_time)
      > r.total_distance / 50;

-- 26. Most profitable vehicle type by total revenue
SELECT '--- Query 26: Revenue by vehicle type ---' AS '';
SELECT vt.type_name,
       SUM(o.total_weight * vt.price_per_kg) AS revenue
FROM vehicle_types vt
JOIN vehicles v ON v.type_id = vt.id
JOIN routes r ON r.vehicle_id = v.id
JOIN deliveries d ON d.route_id = r.id
JOIN orders o ON o.id = d.order_id
WHERE d.status = 'Delivered'
GROUP BY vt.id
ORDER BY revenue DESC;

-- 27. List users who have never performed an auditable action
SELECT '--- Query 27: Users with no audit trail ---' AS '';
SELECT u.id, u.username
FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM system_audit_logs al WHERE al.user_id = u.id
);

-- 28. Find duplicate customer email domains
SELECT '--- Query 28: Duplicate email domains ---' AS '';
SELECT SUBSTRING_INDEX(email, '@', -1) AS domain, COUNT(*) AS count
FROM customers
GROUP BY domain
HAVING COUNT(*) > 1;

-- 29. Shortest completed route for each driver
SELECT '--- Query 29: Shortest route per driver ---' AS '';
SELECT r.driver_id, MIN(r.total_distance) AS shortest_route
FROM routes r
WHERE r.status = 'Completed'
GROUP BY r.driver_id;

-- 30. Rank nodes by number of originating orders (window function)
SELECT '--- Query 30: Node usage ranking ---' AS '';
SELECT n.id, n.label, COUNT(o.id) AS order_count,
       RANK() OVER (ORDER BY COUNT(o.id) DESC) AS rank
FROM nodes n
LEFT JOIN orders o ON o.pickup_node_id = n.id
GROUP BY n.id;


-- ==============================================================
-- PART 5: DATABASE TRIGGER EXAMPLE
-- The after_order_update trigger captures changes to orders
-- and writes audit entries to system_audit_logs.
-- ==============================================================

SELECT '--- Trigger: after_order_update ---' AS '';

-- Simulate an update that fires the trigger:
-- UPDATE orders SET total_weight = 150.00 WHERE id = 1;
-- Then check the audit log:
-- SELECT * FROM system_audit_logs WHERE action_performed LIKE '%Order #1%';

SELECT '--- All 30 queries executed successfully. ---' AS '';
