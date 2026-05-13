USE delivery_system;

-- 1. Security & Roles
INSERT INTO roles (role_name) VALUES ('Admin'), ('Manager'), ('Driver'), ('Customer');
INSERT INTO permissions (perm_key) VALUES ('manage_users'), ('create_routes'), ('update_delivery_status'), ('view_personal_orders');
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 1), (2, 2), (3, 3), (4, 4);

-- 2. Infrastructure
INSERT INTO nodes (x_coord, y_coord, label) VALUES 
(100.0, 100.0, 'Central Warehouse'),
(250.0, 150.0, 'North Distribution Point'),
(150.0, 400.0, 'West Residential Hub'),
(500.0, 500.0, 'East Business Park'),
(300.0, 300.0, 'Midtown Sorting Center');

INSERT INTO edges (node_a_id, node_b_id, distance_units, speed_limit) VALUES 
(1, 2, 158.1, 50),
(2, 4, 430.1, 80),
(1, 3, 304.1, 60),
(3, 5, 180.2, 40),
(5, 4, 282.8, 70);

-- 3. Personnel
INSERT INTO staff (first_name, last_name, position, hire_date) VALUES 
('Alice', 'Vance', 'Logistics Manager', '2024-01-15'),
('Bob', 'Smith', 'Senior Driver', '2024-02-10');

INSERT INTO customers (first_name, last_name, email, phone) VALUES 
('Charlie', 'Brown', 'charlie@example.com', '+37060000001'),
('Dana', 'White', 'dana@example.com', '+37060000002');

INSERT INTO users (username, password_hash, role_id, staff_id) VALUES 
('admin_user', 'hashed_pw_123', 1, 1);

-- 4. Fleet
INSERT INTO vehicle_types (type_name, fuel_rate, max_weight_capacity) VALUES 
('Light Electric Van', 0.12, 500.0),
('Heavy Diesel Truck', 0.45, 3000.0);

INSERT INTO vehicles (type_id, license_plate, current_status) VALUES 
(1, 'EV-101', 'Available'),
(2, 'TR-999', 'On Route');

-- 5. Operations
-- Note: Using 'total_weight' to match your schema
INSERT INTO orders (customer_id, pickup_node_id, dropoff_node_id, total_weight, status) VALUES 
(1, 1, 4, 25.5, 'Pending'),
(2, 3, 5, 10.0, 'In Transit');

INSERT INTO routes (vehicle_id, driver_id, planned_date, total_distance) VALUES 
(2, 2, '2026-05-13', 712.9);

INSERT INTO route_segments (route_id, edge_id, sequence_order) VALUES 
(1, 1, 1),
(1, 2, 2);

INSERT INTO deliveries (order_id, route_id, status) VALUES 
(1, 1, 'Pending');