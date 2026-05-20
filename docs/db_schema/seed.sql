USE delivery_system;

-- 1. Security & Roles
INSERT INTO roles (role_name) VALUES ('Admin'), ('Manager'), ('Dispatcher'), ('Driver'), ('Customer');

-- All 21 permissions organized by domain
INSERT INTO permissions (perm_key) VALUES
  -- Nodes / Map (4)
  ('manage_nodes'), ('manage_edges'), ('manage_regions'), ('manage_locations'),
  -- Routes (2)
  ('manage_routes'), ('update_route_status'),
  -- Fleet (3)
  ('manage_vehicles'), ('manage_vehicle_types'), ('manage_maintenance'),
  -- Users (3)
  ('manage_users'), ('manage_staff'), ('manage_customers'),
  -- Orders (4)
  ('manage_orders'), ('update_order_status'), ('view_all_orders'), ('view_personal_orders'),
  -- Deliveries (2)
  ('manage_deliveries'), ('update_delivery_status'),
  -- Financials (2)
  ('view_financials'), ('manage_financials'),
  -- Customer Info (1)
  ('view_customer_info');

-- Role assignments (using INSERT SELECT for clarity)
-- Admin (role_id=1): all permissions
INSERT INTO role_permissions (role_id, permission_id)
  SELECT 1, id FROM permissions;

-- Manager (role_id=2): operations + finance + staff/ fleet management
INSERT INTO role_permissions (role_id, permission_id)
  SELECT 2, id FROM permissions WHERE perm_key IN (
    'manage_nodes', 'manage_edges',
    'manage_routes', 'update_route_status',
    'manage_orders', 'update_order_status', 'view_all_orders',
    'manage_deliveries', 'update_delivery_status',
    'view_financials', 'view_customer_info',
    'manage_staff', 'manage_vehicles', 'manage_maintenance'
  );

-- Dispatcher (role_id=3): day-to-day operations only
INSERT INTO role_permissions (role_id, permission_id)
  SELECT 3, id FROM permissions WHERE perm_key IN (
    'view_all_orders', 'update_order_status',
    'manage_routes', 'update_route_status',
    'update_delivery_status'
  );

-- Driver (role_id=4): status updates + personal visibility
INSERT INTO role_permissions (role_id, permission_id)
  SELECT 4, id FROM permissions WHERE perm_key IN (
    'update_delivery_status', 'update_route_status',
    'view_personal_orders'
  );

-- Customer (role_id=5): own orders only
INSERT INTO role_permissions (role_id, permission_id)
  SELECT 5, id FROM permissions WHERE perm_key IN (
    'view_personal_orders'
  );

-- 2. Map Regions
INSERT INTO map_regions (region_name, risk_level) VALUES
('Central District', 'Low'),
('Industrial Zone', 'Medium'),
('Suburban Area', 'Low');

-- 3. Infrastructure
INSERT INTO nodes (x_coord, y_coord, label, map_region_id) VALUES 
(100.0, 100.0, 'Central Warehouse', 1),
(250.0, 150.0, 'North Distribution Point', 1),
(150.0, 400.0, 'West Residential Hub', 3),
(500.0, 500.0, 'East Business Park', 2),
(300.0, 300.0, 'Midtown Sorting Center', 1);

INSERT INTO edges (node_a_id, node_b_id, distance_units, speed_limit, map_region_id) VALUES 
(1, 2, 158.1, 50, 1),
(2, 4, 430.1, 80, 2),
(1, 3, 304.1, 60, 1),
(3, 5, 180.2, 40, 3),
(5, 4, 282.8, 70, 2);

-- 4. Personnel
INSERT INTO staff (first_name, last_name, position, hire_date) VALUES 
('Alice', 'Vance', 'Logistics Manager', '2024-01-15'),
('Bob', 'Smith', 'Senior Driver', '2024-02-10');

INSERT INTO customers (first_name, last_name, email, phone) VALUES 
('Charlie', 'Brown', 'charlie@example.com', '+37060000001'),
('Dana', 'White', 'dana@example.com', '+37060000002');

INSERT INTO users (username, password_hash, role_id, staff_id) VALUES 
('admin_user', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 1, 1);

-- 5. Fleet
INSERT INTO vehicle_types (type_name, fuel_rate, max_weight_capacity, price_per_kg) VALUES 
('Light Electric Van', 0.12, 500.0, 8.5000),
('Heavy Diesel Truck', 0.45, 3000.0, 12.0000);

INSERT INTO vehicles (type_id, license_plate, current_status) VALUES 
(1, 'EV-101', 'Available'),
(2, 'TR-999', 'On Route');

-- 6. Operations
INSERT INTO orders (customer_id, pickup_node_id, dropoff_node_id, total_weight, status) VALUES 
(1, 1, 4, 25.5, 'Pending'),
(2, 3, 5, 10.0, 'In Transit');

INSERT INTO routes (vehicle_id, driver_id, planned_date, total_distance, status) VALUES 
(2, 2, '2026-05-13', 712.9, 'Active');

INSERT INTO route_segments (route_id, edge_id, sequence_order) VALUES 
(1, 1, 1),
(1, 2, 2);

INSERT INTO deliveries (order_id, route_id, status) VALUES 
(1, 1, 'Pending');
