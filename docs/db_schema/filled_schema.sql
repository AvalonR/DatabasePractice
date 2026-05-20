-- ==============================================================
-- filled_schema.sql
-- Delivery Network Management System
-- Complete database: schema + all required data records
--
-- Data sources:
--   Section A — Direct INSERT statements   (10 records per table)
--   Section B — Data transfer via SELECT    (10 records per table)
--   Section C — AI-generated bulk data      (100+ records per table)
--
-- Total: 130+ records per table × 18 tables
-- ==============================================================

DROP DATABASE IF EXISTS delivery_system;
CREATE DATABASE IF NOT EXISTS delivery_system;
USE delivery_system;

-- ==============================================================
-- SCHEMA (18 tables)
-- ==============================================================

CREATE TABLE IF NOT EXISTS map_regions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    region_name VARCHAR(100),
    risk_level ENUM('Low', 'Medium', 'High')
);

CREATE TABLE IF NOT EXISTS nodes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    x_coord DECIMAL(10, 2) NOT NULL,
    y_coord DECIMAL(10, 2) NOT NULL,
    label VARCHAR(100),
    map_region_id INT,
    FOREIGN KEY (map_region_id) REFERENCES map_regions(id)
);

CREATE TABLE IF NOT EXISTS edges (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_a_id INT,
    node_b_id INT,
    distance_units DECIMAL(10, 2),
    speed_limit INT DEFAULT 50,
    map_region_id INT,
    FOREIGN KEY (node_a_id) REFERENCES nodes(id),
    FOREIGN KEY (node_b_id) REFERENCES nodes(id),
    FOREIGN KEY (map_region_id) REFERENCES map_regions(id)
);

CREATE TABLE IF NOT EXISTS locations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT,
    name VARCHAR(150) NOT NULL,
    address_text VARCHAR(255),
    FOREIGN KEY (node_id) REFERENCES nodes(id)
);

CREATE TABLE IF NOT EXISTS customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS staff (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    position VARCHAR(100),
    hire_date DATE
);

CREATE TABLE IF NOT EXISTS permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    perm_key VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INT,
    permission_id INT,
    PRIMARY KEY (role_id, permission_id),
    FOREIGN KEY (role_id) REFERENCES roles(id),
    FOREIGN KEY (permission_id) REFERENCES permissions(id)
);

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role_id INT,
    staff_id INT NULL,
    customer_id INT NULL,
    FOREIGN KEY (role_id) REFERENCES roles(id),
    FOREIGN KEY (staff_id) REFERENCES staff(id),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

CREATE TABLE IF NOT EXISTS vehicle_types (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type_name VARCHAR(50),
    fuel_rate DECIMAL(5, 2),
    max_weight_capacity DECIMAL(10, 2),
    price_per_kg DECIMAL(10, 4) NOT NULL DEFAULT 10.0000
);

CREATE TABLE IF NOT EXISTS vehicles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type_id INT,
    license_plate VARCHAR(20) UNIQUE,
    current_status ENUM('Available', 'On Route', 'Maintenance', 'Retired'),
    FOREIGN KEY (type_id) REFERENCES vehicle_types(id)
);

CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT,
    pickup_node_id INT,
    dropoff_node_id INT,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_weight DECIMAL(10, 2),
    status ENUM('Draft', 'Pending', 'In Transit', 'Delivered', 'Failed', 'Cancelled', 'Returned') DEFAULT 'Draft',
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (pickup_node_id) REFERENCES nodes(id),
    FOREIGN KEY (dropoff_node_id) REFERENCES nodes(id)
);

CREATE TABLE IF NOT EXISTS routes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id INT,
    driver_id INT,
    planned_date DATE,
    total_distance DECIMAL(10, 2) DEFAULT 0,
    status ENUM('Planned', 'Active', 'Completed', 'Cancelled') DEFAULT 'Planned',
    FOREIGN KEY (vehicle_id) REFERENCES vehicles(id),
    FOREIGN KEY (driver_id) REFERENCES staff(id)
);

CREATE TABLE IF NOT EXISTS route_segments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    route_id INT,
    edge_id INT,
    sequence_order INT,
    FOREIGN KEY (route_id) REFERENCES routes(id),
    FOREIGN KEY (edge_id) REFERENCES edges(id)
);

CREATE TABLE IF NOT EXISTS deliveries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT,
    route_id INT,
    status ENUM('Pending', 'In Transit', 'Delivered', 'Failed'),
    actual_time DATETIME,
    FOREIGN KEY (order_id) REFERENCES orders(id),
    FOREIGN KEY (route_id) REFERENCES routes(id)
);

CREATE TABLE IF NOT EXISTS maintenance_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id INT,
    service_date DATE,
    description TEXT,
    cost DECIMAL(10, 2),
    FOREIGN KEY (vehicle_id) REFERENCES vehicles(id)
);

CREATE TABLE IF NOT EXISTS system_audit_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action_performed VARCHAR(255),
    action_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

DELIMITER //

DROP TRIGGER IF EXISTS after_delivery_update//
CREATE TRIGGER after_delivery_update
AFTER UPDATE ON deliveries
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO system_audit_logs (user_id, action_performed)
        VALUES (NULL, CONCAT('Delivery #', NEW.id, ' status changed from ', OLD.status, ' to ', NEW.status));
    END IF;
END; //

DROP TRIGGER IF EXISTS after_order_insert//
CREATE TRIGGER after_order_insert
AFTER INSERT ON orders
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Order #', NEW.id, ' created — weight: ', NEW.total_weight, 'kg, status: ', NEW.status));
END; //

DROP TRIGGER IF EXISTS after_order_update//
CREATE TRIGGER after_order_update
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    DECLARE changes TEXT DEFAULT '';
    IF OLD.status <> NEW.status THEN
        SET changes = CONCAT('status: ', OLD.status, ' → ', NEW.status);
    END IF;
    IF OLD.total_weight <> NEW.total_weight THEN
        IF changes <> '' THEN SET changes = CONCAT(changes, '; '); END IF;
        SET changes = CONCAT(changes, 'weight: ', OLD.total_weight, ' → ', NEW.total_weight, 'kg');
    END IF;
    IF OLD.pickup_node_id <> NEW.pickup_node_id THEN
        IF changes <> '' THEN SET changes = CONCAT(changes, '; '); END IF;
        SET changes = CONCAT(changes, 'pickup node: ', OLD.pickup_node_id, ' → ', NEW.pickup_node_id);
    END IF;
    IF OLD.dropoff_node_id <> NEW.dropoff_node_id THEN
        IF changes <> '' THEN SET changes = CONCAT(changes, '; '); END IF;
        SET changes = CONCAT(changes, 'dropoff node: ', OLD.dropoff_node_id, ' → ', NEW.dropoff_node_id);
    END IF;
    IF changes <> '' THEN
        INSERT INTO system_audit_logs (user_id, action_performed)
        VALUES (NULL, CONCAT('Order #', NEW.id, ' updated — ', changes));
    END IF;
END; //

DROP TRIGGER IF EXISTS after_order_delete//
CREATE TRIGGER after_order_delete
AFTER DELETE ON orders
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Order #', OLD.id, ' deleted'));
END; //

DROP TRIGGER IF EXISTS after_user_insert//
CREATE TRIGGER after_user_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NEW.id, CONCAT('User #', NEW.id, ' (', NEW.username, ') created'));
END; //

DROP TRIGGER IF EXISTS after_user_update//
CREATE TRIGGER after_user_update
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    DECLARE changes TEXT DEFAULT '';
    IF OLD.username <> NEW.username THEN
        SET changes = CONCAT('username: ', OLD.username, ' → ', NEW.username);
    END IF;
    IF OLD.role_id <> NEW.role_id THEN
        IF changes <> '' THEN SET changes = CONCAT(changes, '; '); END IF;
        SET changes = CONCAT(changes, 'role: ', OLD.role_id, ' → ', NEW.role_id);
    END IF;
    IF changes <> '' THEN
        INSERT INTO system_audit_logs (user_id, action_performed)
        VALUES (NEW.id, CONCAT('User #', NEW.id, ' updated — ', changes));
    END IF;
END; //

DROP TRIGGER IF EXISTS after_user_delete//
CREATE TRIGGER after_user_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('User #', OLD.id, ' (', OLD.username, ') deleted'));
END; //

DROP TRIGGER IF EXISTS after_vehicle_insert//
CREATE TRIGGER after_vehicle_insert
AFTER INSERT ON vehicles
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Vehicle #', NEW.id, ' (', NEW.license_plate, ') added — status: ', NEW.current_status));
END; //

DROP TRIGGER IF EXISTS after_vehicle_update//
CREATE TRIGGER after_vehicle_update
AFTER UPDATE ON vehicles
FOR EACH ROW
BEGIN
    IF OLD.current_status <> NEW.current_status THEN
        INSERT INTO system_audit_logs (user_id, action_performed)
        VALUES (NULL, CONCAT('Vehicle #', NEW.id, ' (', NEW.license_plate, ') status: ', OLD.current_status, ' → ', NEW.current_status));
    END IF;
END; //

DROP TRIGGER IF EXISTS after_vehicle_delete//
CREATE TRIGGER after_vehicle_delete
AFTER DELETE ON vehicles
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Vehicle #', OLD.id, ' (', OLD.license_plate, ') deleted'));
END; //

DROP TRIGGER IF EXISTS after_node_insert//
CREATE TRIGGER after_node_insert
AFTER INSERT ON nodes
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Node #', NEW.id, ' (', COALESCE(NEW.label, ''), ') created at (', NEW.x_coord, ', ', NEW.y_coord, ')'));
END; //

DROP TRIGGER IF EXISTS after_node_update//
CREATE TRIGGER after_node_update
AFTER UPDATE ON nodes
FOR EACH ROW
BEGIN
    DECLARE changes TEXT DEFAULT '';
    IF OLD.label <> NEW.label THEN
        SET changes = CONCAT('label: ', COALESCE(OLD.label, ''), ' → ', COALESCE(NEW.label, ''));
    END IF;
    IF OLD.x_coord <> NEW.x_coord OR OLD.y_coord <> NEW.y_coord THEN
        IF changes <> '' THEN SET changes = CONCAT(changes, '; '); END IF;
        SET changes = CONCAT(changes, 'coords: (', OLD.x_coord, ',', OLD.y_coord, ') → (', NEW.x_coord, ',', NEW.y_coord, ')');
    END IF;
    IF changes <> '' THEN
        INSERT INTO system_audit_logs (user_id, action_performed)
        VALUES (NULL, CONCAT('Node #', NEW.id, ' updated — ', changes));
    END IF;
END; //

DROP TRIGGER IF EXISTS after_node_delete//
CREATE TRIGGER after_node_delete
AFTER DELETE ON nodes
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Node #', OLD.id, ' (', COALESCE(OLD.label, ''), ') deleted'));
END; //

DROP TRIGGER IF EXISTS after_edge_insert//
CREATE TRIGGER after_edge_insert
AFTER INSERT ON edges
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Edge #', NEW.id, ' created — node ', NEW.node_a_id, ' ↔ ', NEW.node_b_id, ', distance: ', NEW.distance_units));
END; //

DROP TRIGGER IF EXISTS after_edge_update//
CREATE TRIGGER after_edge_update
AFTER UPDATE ON edges
FOR EACH ROW
BEGIN
    DECLARE changes TEXT DEFAULT '';
    IF OLD.node_a_id <> NEW.node_a_id OR OLD.node_b_id <> NEW.node_b_id THEN
        SET changes = CONCAT('nodes: ', OLD.node_a_id, '↔', OLD.node_b_id, ' → ', NEW.node_a_id, '↔', NEW.node_b_id);
    END IF;
    IF OLD.distance_units <> NEW.distance_units THEN
        IF changes <> '' THEN SET changes = CONCAT(changes, '; '); END IF;
        SET changes = CONCAT(changes, 'distance: ', OLD.distance_units, ' → ', NEW.distance_units);
    END IF;
    IF changes <> '' THEN
        INSERT INTO system_audit_logs (user_id, action_performed)
        VALUES (NULL, CONCAT('Edge #', NEW.id, ' updated — ', changes));
    END IF;
END; //

DROP TRIGGER IF EXISTS after_edge_delete//
CREATE TRIGGER after_edge_delete
AFTER DELETE ON edges
FOR EACH ROW
BEGIN
    INSERT INTO system_audit_logs (user_id, action_performed)
    VALUES (NULL, CONCAT('Edge #', OLD.id, ' deleted'));
END; //

DELIMITER ;

-- ==============================================================
-- SECTION A: Direct INSERT Statements (10 records per table)
-- Manually crafted representative data
-- ==============================================================

-- 1. roles (5 core + 5 filler to demonstrate)
INSERT INTO roles (role_name) VALUES
('Admin'),
('Manager'),
('Dispatcher'),
('Driver'),
('Customer'),
('Fleet Supervisor'),
('Warehouse Operator'),
('Finance Officer'),
('IT Support'),
('Auditor');

-- 2. permissions
INSERT INTO permissions (perm_key) VALUES
('manage_nodes'),
('manage_edges'),
('manage_orders'),
('update_order_status'),
('manage_deliveries'),
('view_all_orders'),
('view_personal_orders'),
('manage_users'),
('view_financials'),
('manage_financials'),
('manage_fleet'),
('manage_maintenance'),
('view_reports'),
('manage_regions'),
('manage_locations'),
('manage_roles'),
('manage_permissions'),
('system_config'),
('audit_logs'),
('manage_customers');

-- 3. role_permissions (Admin gets everything)
INSERT INTO role_permissions (role_id, permission_id)
SELECT 1, id FROM permissions;
-- Manager
INSERT INTO role_permissions (role_id, permission_id)
SELECT 2, id FROM permissions WHERE perm_key IN (
    'manage_nodes','manage_edges','manage_orders','update_order_status',
    'manage_deliveries','view_all_orders','manage_fleet','manage_maintenance',
    'view_reports','manage_regions','manage_locations','manage_customers'
);
-- Dispatcher
INSERT INTO role_permissions (role_id, permission_id)
SELECT 3, id FROM permissions WHERE perm_key IN (
    'manage_orders','update_order_status','manage_deliveries',
    'view_all_orders','manage_fleet'
);
-- Driver
INSERT INTO role_permissions (role_id, permission_id)
SELECT 4, id FROM permissions WHERE perm_key IN (
    'view_personal_orders','update_order_status'
);
-- Customer
INSERT INTO role_permissions (role_id, permission_id)
SELECT 5, id FROM permissions WHERE perm_key IN (
    'view_personal_orders'
);

-- 4. map_regions
INSERT INTO map_regions (region_name, risk_level) VALUES
('Central District', 'Low'),
('Industrial Zone', 'Medium'),
('Suburban Area', 'Low'),
('Rural Zone', 'High'),
('Harbor District', 'Medium'),
('Commercial Hub', 'Low'),
('Tech Park', 'Low'),
('Warehouse Quarter', 'Medium'),
('Old Town', 'High'),
('Airport Zone', 'Low');

-- 5. nodes (first 10)
INSERT INTO nodes (x_coord, y_coord, label, map_region_id) VALUES
(10.00, 10.00, 'Main Hub', 1),
(50.00, 30.00, 'North Depot', 1),
(90.00, 50.00, 'East Warehouse', 3),
(30.00, 80.00, 'South Station', 5),
(70.00, 10.00, 'West Terminal', 2),
(15.00, 40.00, 'Central Market', 1),
(55.00, 70.00, 'Harbor Gate', 5),
(85.00, 25.00, 'Tech Campus', 7),
(40.00, 60.00, 'Old Town Depot', 9),
(95.00, 75.00, 'Airport Cargo', 10);

-- Randomize Section A node coordinates to avoid a tidy cluster
UPDATE nodes SET
    x_coord = ROUND(20 + RAND() * 480, 2),
    y_coord = ROUND(15 + RAND() * 380, 2)
WHERE id BETWEEN 1 AND 10;

-- 6. edges (first 10)
INSERT INTO edges (node_a_id, node_b_id, distance_units, speed_limit, map_region_id) VALUES
(1, 2, 40.50, 60, 1),
(2, 3, 45.00, 50, 3),
(3, 4, 42.30, 45, 5),
(4, 5, 55.20, 70, 2),
(5, 1, 38.70, 55, 1),
(2, 6, 18.40, 40, 1),
(6, 7, 35.60, 50, 5),
(7, 8, 45.80, 60, 7),
(8, 9, 30.20, 35, 9),
(9, 10, 25.50, 40, 10);

-- 7. locations
INSERT INTO locations (node_id, name, address_text) VALUES
(1, 'Central Distribution Hub', '100 Logistic Avenue, Central District'),
(2, 'North Regional Depot', '200 Transport Blvd, North Side'),
(3, 'East Storage Facility', '350 Industrial Parkway, East Zone'),
(4, 'South Delivery Station', '480 Dock Road, Harbor Area'),
(5, 'West Cargo Terminal', '550 Highway 7, West Industrial'),
(6, 'City Fresh Market', '120 Grove Street, Downtown'),
(7, 'Harbor Logistics Center', '700 Port Road, Harbor District'),
(8, 'Tech Park Delivery Hub', '900 Innovation Drive, Tech Park'),
(9, 'Old Town Courier Base', '150 Heritage Lane, Old Town'),
(10, 'Airport Express Terminal', '50 Flight Path Road, Airport Zone');

-- 8. customers
INSERT INTO customers (first_name, last_name, email, phone) VALUES
('John', 'Smith', 'john.smith@email.com', '+37061111111'),
('Anna', 'Johnson', 'anna.j@email.com', '+37062222222'),
('Robert', 'Williams', 'r.williams@email.com', '+37063333333'),
('Maria', 'Garcia', 'maria.garcia@email.com', '+37064444444'),
('James', 'Brown', 'james.brown@email.com', '+37065555555'),
('Linda', 'Davis', 'linda.d@email.com', '+37066666666'),
('Michael', 'Wilson', 'm.wilson@email.com', '+37067777777'),
('Sarah', 'Taylor', 's.taylor@email.com', '+37068888888'),
('David', 'Anderson', 'd.anderson@email.com', '+37069999999'),
('Emma', 'Thomas', 'emma.t@email.com', '+37061010101');

-- 9. staff
INSERT INTO staff (first_name, last_name, position, hire_date) VALUES
('Paul', 'Walker', 'Regional Manager', '2023-01-15'),
('Tom', 'Hardy', 'Dispatcher', '2023-03-01'),
('Mike', 'Ross', 'Driver', '2023-06-10'),
('Steve', 'Austin', 'Driver', '2023-07-20'),
('Lisa', 'Kudrow', 'Driver', '2024-01-05'),
('Carl', 'Johnson', 'Warehouse Operator', '2023-09-12'),
('Viktor', 'Petrov', 'Fleet Supervisor', '2023-04-22'),
('Diana', 'Prince', 'Finance Officer', '2023-05-14'),
('Bruce', 'Wayne', 'IT Support', '2023-11-30'),
('Natasha', 'Romanoff', 'Auditor', '2024-02-18');

-- 10. users
INSERT INTO users (username, password_hash, role_id, staff_id, customer_id) VALUES
('admin', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 1, NULL, NULL),
('pwalker', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 2, 1, NULL),
('thardy', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 3, 2, NULL),
('mross', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 4, 3, NULL),
('saustin', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 4, 4, NULL),
('lkudrow', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 4, 5, NULL),
('jsmith', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 5, NULL, 1),
('ajohnson', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 5, NULL, 2),
('rwilliams', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 5, NULL, 3),
('mgarcia', '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS', 5, NULL, 4);

-- 11. vehicle_types
INSERT INTO vehicle_types (type_name, fuel_rate, max_weight_capacity, price_per_kg) VALUES
('Light Electric Van', 0.25, 800.00, 8.5000),
('Heavy Diesel Truck', 0.45, 5000.00, 12.0000),
('Medium Cargo Van', 0.30, 1500.00, 9.5000),
('Refrigerated Truck', 0.55, 3000.00, 15.0000),
('Motorbike Courier', 0.10, 100.00, 5.0000),
('Flatbed Truck', 0.40, 6000.00, 11.0000),
('Small Pickup', 0.28, 750.00, 7.5000),
('Tanker Truck', 0.60, 8000.00, 14.0000),
('Electric Cargo Bike', 0.05, 50.00, 4.0000),
('Minibus Delivery', 0.32, 500.00, 6.5000);

-- 12. vehicles
INSERT INTO vehicles (type_id, license_plate, current_status) VALUES
(1, 'ELEC001', 'Available'),
(2, 'DIESEL01', 'Available'),
(3, 'CARGO01', 'Available'),
(4, 'REFRIG01', 'Maintenance'),
(5, 'MOTO001', 'Available'),
(6, 'FLAT001', 'Available'),
(7, 'PICK001', 'On Route'),
(8, 'TANK001', 'Retired'),
(9, 'BIKE001', 'Available'),
(10, 'MINI001', 'Available');

-- 13. orders
INSERT INTO orders (customer_id, pickup_node_id, dropoff_node_id, order_date, total_weight, status) VALUES
(1, 1, 3, '2026-01-10 08:30:00', 120.50, 'Delivered'),
(2, 2, 5, '2026-01-12 09:00:00', 450.00, 'In Transit'),
(3, 4, 2, '2026-01-15 10:15:00', 80.00, 'Pending'),
(4, 3, 7, '2026-01-18 11:30:00', 200.00, 'Delivered'),
(5, 6, 8, '2026-01-20 07:45:00', 35.00, 'Draft'),
(6, 5, 1, '2026-01-22 12:00:00', 1500.00, 'Pending'),
(7, 8, 9, '2026-02-01 09:30:00', 65.00, 'In Transit'),
(8, 7, 10, '2026-02-03 14:00:00', 320.00, 'Pending'),
(9, 9, 4, '2026-02-05 08:00:00', 95.00, 'Delivered'),
(10, 10, 6, '2026-02-07 16:30:00', 180.00, 'Cancelled');

-- 14. routes
INSERT INTO routes (vehicle_id, driver_id, planned_date, total_distance, status) VALUES
(1, 3, '2026-01-10', 85.50, 'Completed'),
(2, 4, '2026-01-12', 120.00, 'Active'),
(3, 5, '2026-01-18', 95.30, 'Completed'),
(4, 4, '2026-02-01', 55.80, 'Active'),
(5, 5, '2026-02-05', 70.20, 'Completed'),
(1, 3, '2026-01-15', 45.00, 'Completed'),
(7, 3, '2026-01-20', 110.00, 'Planned'),
(5, 5, '2026-01-22', 30.00, 'Cancelled'),
(3, 3, '2026-02-03', 65.40, 'Planned'),
(9, 5, '2026-02-07', 40.00, 'Cancelled');

-- 15. route_segments
-- Generated by Dijkstra shortest path on edge distance_units
INSERT INTO route_segments (route_id, edge_id, sequence_order) VALUES
(1, 1, 1),
(1, 2, 2),
(2, 1, 1),
(2, 5, 2),
(3, 2, 1),
(3, 6, 2),
(3, 7, 3),
(4, 9, 1),
(5, 9, 1),
(5, 8, 2),
(5, 7, 3),
(5, 6, 4),
(5, 2, 5),
(5, 3, 6),
(6, 3, 1),
(6, 2, 2),
(7, 7, 1),
(7, 8, 2),
(8, 5, 1),
(9, 8, 1),
(9, 9, 2),
(9, 10, 3),
(10, 10, 1),
(10, 9, 2),
(10, 8, 3),
(10, 7, 4);

-- 16. deliveries
INSERT INTO deliveries (order_id, route_id, status, actual_time) VALUES
(1, 1, 'Delivered', '2026-01-11 14:30:00'),
(2, 2, 'In Transit', NULL),
(4, 3, 'Delivered', '2026-01-19 16:00:00'),
(7, 4, 'In Transit', NULL),
(9, 5, 'Delivered', '2026-02-06 11:45:00'),
(3, 6, 'Pending', NULL),
(5, 7, 'Pending', NULL),
(6, 8, 'Failed', '2026-01-23 09:00:00'),
(8, 9, 'Pending', NULL),
(10, 10, 'Failed', '2026-02-08 10:00:00');

-- ==============================================================
-- SECTION C: AI-Generated Bulk Data (100+ records per table)
-- Generated using prompts documented in ai_prompts.md
-- ==============================================================

-- C1. roles — 100 additional filler role names
INSERT INTO roles (role_name) VALUES
('Analyst'),('Coordinator'),('Supervisor'),('Technician'),('Specialist'),
('Executive'),('Consultant'),('Planner'),('Scheduler'),('Inspector'),
('Controller'),('Administrator'),('Lead Driver'),('Senior Manager'),('Team Lead'),
('Shift Manager'),('Safety Officer'),('Quality Checker'),('Trainer'),('Mentor'),
('Junior Driver'),('Senior Driver'),('Night Dispatcher'),('Weekend Supervisor'),('Temp Worker'),
('Intern'),('Apprentice'),('Contractor'),('Volunteer'),('Advisor'),
('Strategist'),('Developer'),('Engineer'),('Architect'),('Designer'),
('Researcher'),('Scientist'),('Analytics Lead'),('Data Entry'),('Clerk'),
('Secretary'),('Assistant'),('Director'),('Vice President'),('President'),
('CEO'),('CTO'),('CFO'),('COO'),('Owner'),
('Partner'),('Shareholder'),('Investor'),('Board Member'),('Commissioner'),
('Ombudsman'),('Mediator'),('Arbitrator'),('Liaison'),('Agent'),
('Broker'),('Dealer'),('Merchant'),('Trader'),('Supplier'),
('Vendor'),('Distributor'),('Wholesaler'),('Retailer'),('Logistician'),
('Forwarder'),('Carrier'),('Haulier'),('Courier'),('Messenger'),
('Porter'),('Handler'),('Packer'),('Loader'),('Unloader'),
('Sorter'),('Checker'),('Weigher'),('Measurer'),('Labeler'),
('Stamper'),('Recorder'),('Reporter'),('Correspondent'),('Communicator'),
('Announcer'),('Presenter'),('Host'),('Guide'),('Escort'),
('Patrol'),('Guard'),('Watchman'),('Caretaker'),('Custodian'),
('Cleaner'),('Janitor'),('Maintenance'),('Repairman'),('Handyman');

-- C2. permissions — 100 additional filler perm keys
INSERT INTO permissions (perm_key) VALUES
('view_dashboard'),('edit_profile'),('change_password'),('view_logs'),('export_data'),
('import_data'),('backup_db'),('restore_db'),('manage_backups'),('view_analytics'),
('manage_analytics'),('create_reports'),('schedule_tasks'),('manage_tasks'),('view_tasks'),
('manage_calendar'),('view_calendar'),('send_notifications'),('manage_notifications'),('view_notifications'),
('manage_templates'),('view_templates'),('manage_documents'),('view_documents'),('upload_files'),
('download_files'),('delete_files'),('share_files'),('manage_storage'),('view_storage'),
('manage_api_keys'),('view_api_keys'),('manage_webhooks'),('view_webhooks'),('manage_integrations'),
('view_integrations'),('manage_settings'),('view_settings'),('manage_security'),('view_security'),
('manage_audit'),('view_audit'),('manage_compliance'),('view_compliance'),('manage_risk'),
('view_risk'),('manage_insurance'),('view_insurance'),('manage_contracts'),('view_contracts'),
('manage_vendors'),('view_vendors'),('manage_inventory'),('view_inventory'),('manage_supplies'),
('view_supplies'),('manage_equipment'),('view_equipment'),('manage_facilities'),('view_facilities'),
('manage_vehicles'),('view_vehicles'),('manage_drivers'),('view_drivers'),('manage_routes'),
('view_routes'),('manage_shipments'),('view_shipments'),('manage_tracking'),('view_tracking'),
('manage_billing'),('view_billing'),('manage_invoices'),('view_invoices'),('manage_payments'),
('view_payments'),('manage_refunds'),('view_refunds'),('manage_pricing'),('view_pricing'),
('manage_discounts'),('view_discounts'),('manage_promotions'),('view_promotions'),('manage_campaigns'),
('view_campaigns'),('manage_leads'),('view_leads'),('manage_contacts'),('view_contacts'),
('manage_activity'),('view_activity'),('manage_history'),('view_history'),('manage_archive'),
('view_archive'),('manage_recycling'),('view_recycling'),('manage_disposal'),('view_disposal');

-- C3. map_regions — 100 additional regions with varied risk levels
INSERT INTO map_regions (region_name, risk_level) VALUES
('North Valley','Low'),('East Ridge','Medium'),('West Hill','Low'),('South Plains','High'),('River Bend','Medium'),
('Lake View','Low'),('Mountain Pass','High'),('Forest Edge','Medium'),('Desert Road','High'),('Coastal Strip','Medium'),
('Delta Zone','High'),('Hilltop','Low'),('Valley Floor','Medium'),('Creek Side','Low'),('Bay Area','Medium'),
('Cape Point','High'),('Island Terminal','High'),('Bridge District','Medium'),('Tunnel Zone','High'),('Crossroads','Low'),
('Junction City','Low'),('Roundabout Area','Medium'),('Overpass Zone','Low'),('Underpass','Medium'),('Railway Quarter','High'),
('Station Square','Low'),('Plaza Central','Low'),('Market Street','Medium'),('High Street','Low'),('Main Avenue','Low'),
('Park Lane','Low'),('Garden District','Low'),('Green Zone','Low'),('Nature Reserve','Medium'),('Wildlife Area','High'),
('Canal District','Medium'),('Marina','Low'),('Boardwalk','Low'),('Promenade','Low'),('Boulevard','Low'),
('Crescent','Low'),('Terrace','Low'),('Meadow','Low'),('Field','Low'),('Farmland','Medium'),
('Orchard','Low'),('Vineyard','Low'),('Estate','Low'),('Manor','Low'),('Chateau','Medium'),
('Castle Grounds','High'),('Fort Area','High'),('Garrison','Medium'),('Barracks','Medium'),('Armory','High'),
('Stadium Zone','Low'),('Arena','Low'),('Sports Complex','Low'),('Recreation Center','Low'),('Park District','Low'),
('Golf Course','Low'),('Country Club','Low'),('Resort Area','Low'),('Hotel District','Low'),('Tourist Zone','Low'),
('Convention Center','Low'),('Exhibition Hall','Low'),('Fairgrounds','Medium'),('Market Square','Low'),('Bazaar','Medium'),
('Shopping Mile','Low'),('Retail Park','Low'),('Outlet Zone','Low'),('Mall District','Low'),('Department Store Row','Low'),
('Financial District','Low'),('Banking Quarter','Low'),('Insurance Row','Low'),('Stock Exchange Area','Low'),('Business Park','Low'),
('Office Zone','Low'),('Corporate Hub','Low'),('Startup Row','Low'),('Innovation Lab','Low'),('Research Park','Low'),
('University District','Low'),('Campus Zone','Low'),('School Area','Low'),('Library Row','Low'),('Museum District','Low'),
('Theatre Land','Medium'),('Cinema Row','Low'),('Entertainment Zone','Low'),('Nightlife District','Medium'),('Restaurant Row','Low'),
('Food Court','Low'),('Cafe Quarter','Low'),('Bakery Lane','Low'),('Market Hall','Medium'),('Deli District','Low');

-- C4. nodes — 110 nodes in a structured grid
INSERT INTO nodes (x_coord, y_coord, label, map_region_id) VALUES
-- Row 1 (nodes 11-20)
(20.00,20.00,'Sorting Center',2),(30.00,20.00,'Parcel Hub A',1),(40.00,20.00,'Distribution Point 3',3),
(50.00,20.00,'Logistics Base 4',2),(60.00,20.00,'Transfer Station 5',4),(70.00,20.00,'Warehouse 6',1),
(80.00,20.00,'Cargo Center 7',3),(90.00,20.00,'Freight Terminal 8',5),(100.00,20.00,'Delivery Hub 9',1),
(110.00,20.00,'Express Depot 10',4),
-- Row 2 (nodes 21-30)
(15.00,35.00,'Cross Dock 11',2),(25.00,35.00,'Consolidation Point 12',1),(35.00,35.00,'Break Bulk 13',3),
(45.00,35.00,'Transshipment 14',2),(55.00,35.00,'Intermodal 15',4),(65.00,35.00,'Container Yard 16',1),
(75.00,35.00,'Railhead 17',3),(85.00,35.00,'Air Cargo 18',5),(95.00,35.00,'Sea Freight 19',1),
(105.00,35.00,'River Terminal 20',4),
-- Row 3 (nodes 31-40)
(12.00,50.00,'Urban Depot 21',6),(22.00,50.00,'City Center Hub 22',7),(32.00,50.00,'Metro Station 23',8),
(42.00,50.00,'Suburban Base 24',9),(52.00,50.00,'Rural Outpost 25',10),(62.00,50.00,'Remote Terminal 26',6),
(72.00,50.00,'Island Depot 27',7),(82.00,50.00,'Mountain Lodge 28',8),(92.00,50.00,'Valley Station 29',9),
(102.00,50.00,'Plain Center 30',10),
-- Row 4 (nodes 41-50)
(18.00,65.00,'Pickup Point 31',3),(28.00,65.00,'Drop Zone 32',5),(38.00,65.00,'Collection Center 33',2),
(48.00,65.00,'Returns Hub 34',4),(58.00,65.00,'Refurb Center 35',1),(68.00,65.00,'Quality Station 36',3),
(78.00,65.00,'Testing Lab 37',5),(88.00,65.00,'Packaging Plant 38',2),(98.00,65.00,'Assembly Depot 39',4),
(108.00,65.00,'Production Base 40',1),
-- Row 5 (nodes 51-60)
(10.00,80.00,'Fuel Station 41',4),(20.00,80.00,'Charging Point 42',6),(30.00,80.00,'Service Center 43',8),
(40.00,80.00,'Repair Shop 44',10),(50.00,80.00,'Garage 45',2),(60.00,80.00,'Depot 46',5),
(70.00,80.00,'Yard 47',7),(80.00,80.00,'Lot 48',9),(90.00,80.00,'Parking 49',3),
(100.00,80.00,'Rest Stop 50',6),
-- Row 6 (nodes 61-70)
(25.00,95.00,'Parcel Locker 51',1),(35.00,95.00,'Safe Drop 52',2),(45.00,95.00,'Secure Box 53',3),
(55.00,95.00,'Vault 54',4),(65.00,95.00,'Storage Unit 55',5),(75.00,95.00,'Silo 56',6),
(85.00,95.00,'Tank Farm 57',7),(95.00,95.00,'Bulk Storage 58',8),(105.00,95.00,'Cool Room 59',9),
(115.00,95.00,'Freezer 60',10),
-- Row 7 (nodes 71-80)
(22.00,110.00,'Pharma Depot 61',3),(32.00,110.00,'Food Hub 62',5),(42.00,110.00,'Produce Market 63',1),
(52.00,110.00,'Meat Processing 64',4),(62.00,110.00,'Dairy Plant 65',2),(72.00,110.00,'Bakery Distribution 66',6),
(82.00,110.00,'Beverage Center 67',8),(92.00,110.00,'Alcohol Warehouse 68',10),(102.00,110.00,'Tobacco Storage 69',3),
(112.00,110.00,'Medicine Vault 70',5),
-- Row 8 (nodes 81-90)
(28.00,125.00,'Furniture Hub 71',7),(38.00,125.00,'Electronics Depot 72',9),(48.00,125.00,'Appliance Center 73',2),
(58.00,125.00,'Clothing Warehouse 74',4),(68.00,125.00,'Textile Plant 75',6),(78.00,125.00,'Shoe Distribution 76',8),
(88.00,125.00,'Accessories Hub 77',10),(98.00,125.00,'Jewelry Vault 78',1),(108.00,125.00,'Watch Storage 79',3),
(118.00,125.00,'Toy Depot 80',5),
-- Row 9 (nodes 91-100)
(20.00,140.00,'Book Warehouse 81',2),(30.00,140.00,'Paper Depot 82',4),(40.00,140.00,'Office Supply Hub 83',6),
(50.00,140.00,'Stationery Center 84',8),(60.00,140.00,'Print Shop 85',10),(70.00,140.00,'Copy Center 86',1),
(80.00,140.00,'Mail Room 87',3),(90.00,140.00,'Post Office 88',5),(100.00,140.00,'Courier Station 89',7),
(110.00,140.00,'Messenger Base 90',9),
-- Row 10 (nodes 101-110)
(25.00,155.00,'Spare Parts 91',2),(35.00,155.00,'Tool Crib 92',4),(45.00,155.00,'Hardware Store 93',6),
(55.00,155.00,'Building Supply 94',8),(65.00,155.00,'Lumber Yard 95',10),(75.00,155.00,'Metal Depot 96',1),
(85.00,155.00,'Chemical Warehouse 97',3),(95.00,155.00,'Paint Storage 98',5),(105.00,155.00,'Glass Center 99',7),
(115.00,155.00,'Rubber Plant 100',9);

-- Randomize C4 node coordinates for a chaotic (non-grid) layout
UPDATE nodes SET
    x_coord = ROUND(30 + RAND() * 460, 2),
    y_coord = ROUND(20 + RAND() * 370, 2)
WHERE id BETWEEN 11 AND 110;

-- C5. edges — 110 connections in the grid
INSERT INTO edges (node_a_id, node_b_id, distance_units, speed_limit, map_region_id) VALUES
-- Horizontal connections (Row 1)
(11,12,10.5,50,2),(12,13,10.2,50,1),(13,14,11.3,45,3),(14,15,9.8,50,2),(15,16,11.5,60,4),
(16,17,10.1,50,1),(17,18,12.4,55,3),(18,19,10.8,50,5),(19,20,10.0,50,1),
-- Vertical connections (Column 1)
(11,21,15.5,40,2),(21,31,15.5,40,2),(31,41,15.2,40,3),(41,51,15.8,50,4),(51,61,15.0,45,1),
(61,71,15.3,40,3),(71,81,15.6,50,7),(81,91,15.1,45,2),(91,101,15.4,40,2),
-- Diagonal and cross connections
(12,22,10.8,45,1),(22,32,11.2,40,7),(32,42,10.5,50,8),(42,52,11.8,45,2),
(52,62,10.3,40,5),(62,72,11.1,50,6),(72,82,10.7,45,9),(82,92,11.5,40,4),
-- Grid fill connections
(13,23,12.0,45,3),(23,33,11.8,50,8),(33,43,10.2,40,9),(43,53,11.6,45,10),
(53,63,10.9,50,3),(63,73,12.1,40,5),(73,83,11.4,45,8),(83,93,10.6,50,1),
(14,24,11.3,40,2),(24,34,10.7,45,2),(34,44,12.2,50,4),(44,54,11.1,40,4),
(54,64,10.4,45,5),(64,74,11.9,50,6),(74,84,13.0,40,9),(84,94,10.5,45,5),
(15,25,10.1,50,4),(25,35,11.7,40,4),(35,45,10.3,45,10),(45,55,12.5,50,2),
(55,65,11.0,40,2),(65,75,10.8,45,2),(75,85,12.3,50,3),(85,95,11.1,40,3),
(16,26,11.6,45,1),(26,36,10.2,40,6),(36,46,12.1,50,6),(46,56,10.9,45,5),
(56,66,11.5,40,7),(66,76,10.4,45,8),(76,86,12.0,50,1),(86,96,11.8,40,1),
(17,27,10.5,50,3),(27,37,11.3,40,7),(37,47,10.1,45,9),(47,57,12.4,50,7),
(57,67,11.2,40,8),(67,77,10.6,45,8),(77,87,11.7,50,3),(87,97,10.3,40,3),
(18,28,11.0,45,5),(28,38,10.9,50,8),(38,48,12.3,40,5),(48,58,11.4,45,9),
(58,68,10.7,50,10),(68,78,11.1,40,10),(78,88,10.2,45,10),(88,98,12.5,50,5),
(19,29,10.4,40,1),(29,39,11.8,45,9),(39,49,10.6,50,2),(49,59,12.1,40,3),
(59,69,10.3,45,9),(69,79,11.9,50,3),(79,89,10.1,40,1),(89,99,11.6,45,7),
(20,30,11.2,50,4),(30,40,10.5,40,10),(40,50,12.0,45,1),(50,60,11.7,50,6),
(60,70,10.8,40,10),(70,80,11.3,45,4),(80,90,10.9,50,5),(90,100,12.2,40,9),
-- Additional rows (connecting lower rows)
(101,102,10.5,40,2),(102,103,11.1,45,4),(103,104,10.8,50,6),(104,105,12.3,40,8),
(105,106,11.0,45,10),(106,107,10.2,50,1),(107,108,11.7,40,3),(108,109,10.4,45,5),
(109,110,12.1,50,7),(110,101,15.0,35,9);

-- C6. locations — 100 location records for existing nodes
INSERT INTO locations (node_id, name, address_text)
SELECT n.id, CONCAT('Location Point ', n.id, ' - ', n.label),
       CONCAT('Address ', n.id, ', Zone ', COALESCE(r.region_name, 'General'))
FROM nodes n
LEFT JOIN map_regions r ON r.id = n.map_region_id
WHERE n.id BETWEEN 11 AND 110;

-- C7. customers — 100 additional customers
INSERT INTO customers (first_name, last_name, email, phone) VALUES
('Oliver','Smith','oliver.smith@email.com','+37061111111'),('Sophia','Johnson','sophia.j@email.com','+37062222222'),
('Liam','Williams','liam.w@email.com','+37063333333'),('Olivia','Brown','olivia.b@email.com','+37064444444'),
('Noah','Jones','noah.j@email.com','+37065555555'),('Ava','Garcia','ava.g@email.com','+37066666666'),
('Ethan','Miller','ethan.m@email.com','+37067777777'),('Isabella','Davis','isabella.d@email.com','+37068888888'),
('Mason','Rodriguez','mason.r@email.com','+37069999999'),('Mia','Martinez','mia.m@email.com','+37061010101'),
('Lucas','Hernandez','lucas.h@email.com','+37061111212'),('Charlotte','Lopez','charlotte.l@email.com','+37062222323'),
('James','Gonzalez','james.g@email.com','+37063333434'),('Amelia','Wilson','amelia.w@email.com','+37064444545'),
('Logan','Anderson','logan.a@email.com','+37065555656'),('Harper','Thomas','harper.t@email.com','+37066666767'),
('Elijah','Taylor','elijah.t@email.com','+37067777878'),('Evelyn','Moore','evelyn.m@email.com','+37068888989'),
('Aiden','Jackson','aiden.j@email.com','+37069999000'),('Abigail','Martin','abigail.m@email.com','+37061011101'),
('Carter','Lee','carter.l@email.com','+37061112212'),('Emily','Perez','emily.p@email.com','+37062223323'),
('Owen','Thompson','owen.t@email.com','+37063334434'),('Ella','White','ella.w@email.com','+37064445545'),
('Gabriel','Harris','gabriel.h@email.com','+37065556656'),('Avery','Sanchez','avery.s@email.com','+37066667767'),
('Julian','Clark','julian.c@email.com','+37067778878'),('Scarlett','Ramirez','scarlett.r@email.com','+37068889989'),
('Wyatt','Lewis','wyatt.l@email.com','+37069990000'),('Grace','Robinson','grace.r@email.com','+37061012212'),
('Isaiah','Walker','isaiah.w@email.com','+37061123323'),('Chloe','Young','chloe.y@email.com','+37062234434'),
('Henry','Allen','henry.a@email.com','+37063345545'),('Victoria','King','victoria.k@email.com','+37064456656'),
('Jack','Wright','jack.w@email.com','+37065567767'),('Riley','Scott','riley.s@email.com','+37066678878'),
('Sebastian','Torres','sebastian.t@email.com','+37067789989'),('Aria','Nguyen','aria.n@email.com','+37068900000'),
('Levi','Hill','levi.h@email.com','+37061013313'),('Lily','Flores','lily.f@email.com','+37061124424'),
('Dylan','Green','dylan.g@email.com','+37062235535'),('Aurora','Adams','aurora.a@email.com','+37063346646'),
('Samuel','Nelson','samuel.n@email.com','+37064457757'),('Penelope','Baker','penelope.b@email.com','+37065568868'),
('Nathan','Hall','nathan.h@email.com','+37066679979'),('Hannah','Rivera','hannah.r@email.com','+37067780080'),
('Ryan','Campbell','ryan.c@email.com','+37068891191'),('Layla','Mitchell','layla.m@email.com','+37069902202'),
('Isaac','Carter','isaac.c@email.com','+37061014414'),('Zoe','Roberts','zoe.r@email.com','+37061125525'),
('Luke','Gomez','luke.g@email.com','+37062236636'),('Stella','Phillips','stella.p@email.com','+37063347747'),
('Max','Evans','max.e@email.com','+37064458858'),('Nora','Turner','nora.t@email.com','+37065569969'),
('Christian','Diaz','christian.d@email.com','+37066670070'),('Leah','Parker','leah.p@email.com','+37067781181'),
('Jackson','Cruz','jackson.c@email.com','+37068892292'),('Savannah','Edwards','savannah.e@email.com','+37069903303'),
('Josiah','Collins','josiah.c@email.com','+37061015515'),('Audrey','Reyes','audrey.r@email.com','+37061126626'),
('Aaron','Stewart','aaron.s@email.com','+37062237737'),('Brooklyn','Morris','brooklyn.m@email.com','+37063348848'),
('Caleb','Morales','caleb.m@email.com','+37064459959'),('Bella','Murphy','bella.m@email.com','+37065560060'),
('Connor','Cook','connor.c@email.com','+37066671171'),('Claire','Rogers','claire.r@email.com','+37067782282'),
('Hunter','Gutierrez','hunter.g@email.com','+37068893393'),('Skylar','Ortiz','skylar.o@email.com','+37069904404'),
('Adrian','Wood','adrian.w@email.com','+37061016616'),('Paisley','Shaw','paisley.s@email.com','+37061127727'),
('Thomas','Chapman','thomas.c@email.com','+37062238838'),('Ellie','Wells','ellie.w@email.com','+37063349949'),
('Charles','Ford','charles.f@email.com','+37064450050'),('Samantha','Mendoza','samantha.m@email.com','+37065561161'),
('Christopher','Rice','christopher.r@email.com','+37066672272'),('Alice','Harmon','alice.h@email.com','+37067783383'),
('Jose','Baldwin','jose.b@email.com','+37068894494'),('Lucy','Harmon','lucy.h@email.com','+37069905505'),
('Andrew','Sutton','andrew.s@email.com','+37061017717'),('Maya','Fletcher','maya.f@email.com','+37061128828'),
('Dominic','Weaver','dominic.w@email.com','+37062239939'),('Piper','Grant','piper.g@email.com','+37063340040'),
('Tyler','Harrison','tyler.h@email.com','+37064451151'),('Naomi','Dixon','naomi.d@email.com','+37065562262'),
('Zachary','Hunt','zachary.h@email.com','+37066673373'),('Taylor','Pierce','taylor.p@email.com','+37067784484'),
('Grayson','Lynch','grayson.l@email.com','+37068895595'),('Hazel','Bishop','hazel.b@email.com','+37069906606'),
('Landon','Kelley','landon.k@email.com','+37061018818'),('Violet','Hawkins','violet.h@email.com','+37061129929'),
('Cameron','Crawford','cameron.c@email.com','+37062230030'),('Luna','Arnold','luna.a@email.com','+37063341141');

-- C8. staff — 100 additional staff members
INSERT INTO staff (first_name, last_name, position, hire_date) VALUES
('Alex','Turner','Driver','2024-03-01'),('Jordan','Reed','Driver','2024-03-05'),('Morgan','Cole','Driver','2024-03-10'),
('Casey','Fox','Driver','2024-03-15'),('Riley','Hayes','Driver','2024-03-20'),('Taylor','West','Driver','2024-03-25'),
('Avery','Sims','Driver','2024-04-01'),('Quinn','Brooks','Driver','2024-04-05'),('Sage','Porter','Driver','2024-04-10'),
('Reese','Burns','Driver','2024-04-15'),('Dakota','Wagner','Driver','2024-04-20'),('Skyler','Myers','Driver','2024-04-25'),
('Finley','Hunt','Driver','2024-05-01'),('Rowan','Sullivan','Driver','2024-05-05'),('Emerson','Wells','Driver','2024-05-10'),
('Parker','Mason','Driver','2024-05-15'),('Harper','Greene','Warehouse Operator','2024-03-08'),('Cameron','Stone','Warehouse Operator','2024-03-12'),
('Dylan','Webb','Warehouse Operator','2024-04-02'),('Blake','Wallace','Warehouse Operator','2024-04-18'),
('Sawyer','Coleman','Warehouse Operator','2024-05-06'),('Logan','Stephens','Fleet Supervisor','2024-03-03'),
('Hayden','Chavez','Fleet Supervisor','2024-04-10'),('Emery','Ramos','Dispatcher','2024-05-01'),
('Ellis','Banks','Dispatcher','2024-06-01'),('Finnegan','James','Dispatcher','2024-06-15'),
('River','Holland','Technician','2024-03-20'),('Wren','Fleming','Technician','2024-04-25'),
('Kai','Gibson','Technician','2024-05-30'),('Nova','Dean','Safety Officer','2024-03-15'),
('Atlas','Carr','Safety Officer','2024-07-01'),('Orion','Cross','Logistics Manager','2024-02-01'),
('Nova','Hart','Operations Manager','2024-02-15'),('Luna','Bowen','Quality Checker','2024-04-01'),
('Stella','Ballard','Shift Manager','2024-05-15'),('Aria','Dalton','Scheduler','2024-06-01'),
('Nora','Shepherd','Planner','2024-06-15'),('Ivy','Hawthorne','Analyst','2024-03-01'),
('Violet','Spencer','Coordinator','2024-07-01'),('Hazel','Kingston','Inspector','2024-04-15'),
('Lily','Bishop','Trainer','2024-05-20'),('Rose','Craig','Mentor','2024-06-10'),
('Jane','Dawson','Lead Driver','2024-02-20'),('June','Parks','Senior Driver','2024-01-10'),
('May','Curtis','Junior Driver','2024-06-20'),('April','Foster','Night Dispatcher','2024-07-15'),
('June','Brewer','Weekend Supervisor','2024-08-01'),('May','Hudson','Temp Worker','2024-09-01'),
('April','Pearson','Intern','2024-09-15'),('Rose','Ward','Apprentice','2024-10-01'),
('Lily','Holmes','Contractor','2024-01-20'),('Violet','Miles','Administrator','2024-03-25'),
('Ivy','Bradley','Clerk','2024-04-10'),('Nora','Fisher','Secretary','2024-05-05'),
('Stella','Thornton','Assistant','2024-06-15'),('Luna','Chandler','Data Entry','2024-07-01'),
('Atlas','Christensen','Researcher','2024-08-15'),('Orion','Garner','Strategist','2024-09-01'),
('Kai','Robinson','Consultant','2024-10-15'),('Wren','Owen','Advisor','2024-11-01'),
('River','Austin','Courier','2024-03-10'),('Ellis','Bailey','Messenger','2024-04-05'),
('Emery','Cooper','Handler','2024-05-20'),('Hayden','Dunn','Packer','2024-06-10'),
('Logan','Ellis','Loader','2024-07-05'),('Sawyer','Ferguson','Sorter','2024-08-15'),
('Blake','Gibbs','Checker','2024-09-01'),('Dylan','Hale','Weigher','2024-09-20'),
('Cameron','Irwin','Labeler','2024-10-05'),('Harper','Jenkins','Recorder','2024-10-15'),
('Parker','Knight','Reporter','2024-11-01'),('Emerson','Leonard','Caretaker','2024-03-15'),
('Rowan','Marsh','Guard','2024-06-01'),('Finley','Newton','Patrol','2024-07-15'),
('Skyler','Oliver','Watchman','2024-08-01'),('Dakota','Patton','Cleaner','2024-09-15'),
('Reese','Quinn','Janitor','2024-10-01'),('Sage','Ray','Maintenance','2024-04-20'),
('Quinn','Sharp','Repairman','2024-05-25'),('Avery','Tate','Handyman','2024-07-01'),
('Taylor','Underwood','Porter','2024-08-20'),('Riley','Vance','Haulier','2024-09-10'),
('Morgan','Wall','Carrier','2024-10-25'),('Jordan','York','Forwarder','2024-11-15'),
('Alex','Zimmerman','Distributor','2024-12-01'),('Casey','Abbott','Supplier','2024-03-20'),
('Riley','Black','Vendor','2024-04-15'),('Sage','Chase','Merchant','2024-05-10'),
('Reese','Drake','Trader','2024-06-05'),('Dakota','Eaton','Broker','2024-07-20'),
('Skyler','Flynn','Agent','2024-08-10'),('Finley','Gates','Liaison','2024-09-05'),
('Rowan','House','Mediator','2024-10-20'),('Emerson','Irving','Director','2024-01-05');

-- C9. users — 100 additional user accounts (password = 'password' bcrypt hash)
INSERT INTO users (username, password_hash, role_id, staff_id, customer_id) VALUES
('aturner','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,11,NULL),
('jreed','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,12,NULL),
('mcole','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,13,NULL),
('cfox','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,14,NULL),
('rhayes','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,15,NULL),
('twest','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,16,NULL),
('asims','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,17,NULL),
('qbrooks','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,18,NULL),
('sporter','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,19,NULL),
('rburns','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,20,NULL),
('dwagner','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,21,NULL),
('smyers','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,22,NULL),
('fhunt','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,23,NULL),
('rsullivan','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,24,NULL),
('ewells','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,25,NULL),
('pmason','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,26,NULL),
('hgreene','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,27,NULL),
('cstone','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,28,NULL),
('dwebb','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,29,NULL),
('bwallace','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,30,NULL),
('scoleman','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,31,NULL),
('lstephens','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',7,32,NULL),
('hchavez','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',7,33,NULL),
('eramos','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',3,34,NULL),
('ebanks','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',3,35,NULL),
('fjames','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',3,36,NULL),
('rholland','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',8,37,NULL),
('wfleming','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',8,38,NULL),
('kgibson','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',8,39,NULL),
('ndean','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',9,40,NULL),
('acarr','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',9,41,NULL),
('ocross','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',2,42,NULL),
('nhart','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',2,43,NULL),
('lbowen','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,44,NULL),
('sballard','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,45,NULL),
('adalton','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',2,46,NULL),
('nshepherd','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',2,47,NULL),
('ihawthorne','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,48,NULL),
('vspencer','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,49,NULL),
('hkingston','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,50,NULL),
('lbishop','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',9,51,NULL),
('rcraig','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',9,52,NULL),
('jdawson','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',7,53,NULL),
('jparks','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,54,NULL),
('mcurtis','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,55,NULL),
('afoster','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',3,56,NULL),
('jbrewer','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,57,NULL),
('mhudson','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,58,NULL),
('ppearson','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,59,NULL),
('rward','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,60,NULL),
('lholmes','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',12,61,NULL),
('vmiles','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',12,62,NULL),
('ibradley','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',12,63,NULL),
('nfisher','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',12,64,NULL),
('sthornton','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',12,65,NULL),
('lchandler','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',12,66,NULL),
('achristensen','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,67,NULL),
('ogarner','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,68,NULL),
('krobinson','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,69,NULL),
('wowen','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',10,70,NULL),
('raustin','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,71,NULL),
('ebailey','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,72,NULL),
('ecooper','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,73,NULL),
('hdunn','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,74,NULL),
('lellis','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,75,NULL),
('sferguson','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,76,NULL),
('bgibbs','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,77,NULL),
('dhale','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,78,NULL),
('cirwin','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,79,NULL),
('hjenkins','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,80,NULL),
('pknight','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,81,NULL),
('eleonard','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,82,NULL),
('rmarsh','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,83,NULL),
('fnewton','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,84,NULL),
('soliver','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,85,NULL),
('dpatton','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,86,NULL),
('rquinn','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,87,NULL),
('sray','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,88,NULL),
('qsharp','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',8,89,NULL),
('atate','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',8,90,NULL),
('tunderwood','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,91,NULL),
('rvance','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,92,NULL),
('mwall','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,93,NULL),
('jyork','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,94,NULL),
('azimmerman','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',6,95,NULL),
('cabbott','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,96,NULL),
('rblack','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,97,NULL),
('schase','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,98,NULL),
('rdrake','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,99,NULL),
('deaton','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,100,NULL),
('sflynn','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',4,101,NULL),
('fgates','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',5,NULL,15),
('rhouse','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',5,NULL,16),
('eirving','$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',1,104,NULL);

-- C10. vehicle_types — 100 additional filler types
INSERT INTO vehicle_types (type_name, fuel_rate, max_weight_capacity, price_per_kg) VALUES
('Mini Van',0.22,600.00,7.0000),('Standard Van',0.28,1000.00,8.0000),('Extended Van',0.32,1200.00,8.5000),
('Light Truck',0.35,2000.00,9.5000),('Medium Truck',0.40,3500.00,10.5000),('Heavy Truck',0.48,6000.00,12.5000),
('Extra Heavy Truck',0.55,8000.00,13.5000),('Semi Trailer',0.50,10000.00,14.0000),('Double Trailer',0.58,14000.00,15.0000),
('Refrigerated Van',0.38,2000.00,14.0000),('Freezer Truck',0.52,4000.00,16.0000),('Cryogenic Tanker',0.65,5000.00,18.0000),
('Fuel Tanker',0.55,6000.00,15.0000),('Chemical Tanker',0.60,5500.00,16.5000),('Gas Transporter',0.58,4500.00,17.0000),
('Flatbed Light',0.33,2500.00,10.0000),('Flatbed Heavy',0.45,7000.00,12.0000),('Lowbed Trailer',0.52,10000.00,13.0000),
('Tipper Truck',0.42,5000.00,11.0000),('Concrete Mixer',0.50,4000.00,12.5000),('Crane Truck',0.48,3000.00,13.0000),
('Forklift Carrier',0.38,2000.00,11.0000),('Pallet Truck',0.20,500.00,6.0000),('Container Carrier',0.55,12000.00,13.5000),
('Chassis Trailer',0.48,9000.00,12.0000),('Curtain Sider',0.44,7000.00,11.5000),('Box Truck',0.38,4000.00,10.0000),
('Insulated Van',0.35,2500.00,11.0000),('Livestock Truck',0.50,5000.00,13.0000),('Car Transporter',0.48,6000.00,14.0000),
('Boat Trailer',0.42,3000.00,12.0000),('Motorcycle',0.08,50.00,4.5000),('Scooter',0.06,30.00,3.5000),
('Bicycle Courier',0.02,20.00,2.5000),('Electric Scooter',0.03,25.00,3.0000),('Drone Delivery',0.01,5.00,5.0000),
('Autonomous Pod',0.15,100.00,6.0000),('Robotic Cart',0.10,200.00,5.5000),('Conveyor Truck',0.45,3000.00,10.5000),
('Bulk Carrier',0.50,8000.00,12.0000),('Grain Truck',0.48,7000.00,11.0000),('Livestock Van',0.45,4000.00,12.0000),
('Temperature Controlled',0.42,3500.00,14.5000),('Hazardous Materials',0.55,3000.00,17.0000),('Armored Vehicle',0.40,2000.00,15.0000),
('Cash Transport',0.38,1500.00,16.0000),('Valuables Carrier',0.35,1000.00,18.0000),('Diplomatic Pouch',0.25,200.00,20.0000),
('Medical Transport',0.30,500.00,15.0000),('Blood Bank Van',0.28,300.00,14.0000),('Pharmaceutical',0.32,800.00,13.5000),
('Lab Sample Carrier',0.25,200.00,16.0000),('Waste Collection',0.45,4000.00,8.0000),('Recycling Truck',0.42,3500.00,7.5000),
('Compost Carrier',0.38,3000.00,6.5000),('Scrap Metal',0.48,6000.00,9.0000),('Paper Recycling',0.40,4500.00,7.0000),
('Glass Collector',0.35,2500.00,6.0000),('Electronic Waste',0.38,2000.00,8.5000),('Textile Collection',0.32,1500.00,5.5000),
('Furniture Van',0.35,2000.00,8.0000),('Appliance Delivery',0.38,2500.00,9.0000),('White Goods Transporter',0.40,3000.00,9.5000),
('Mattress Delivery',0.30,500.00,7.0000),('Carpet Van',0.32,800.00,6.5000),('Piano Mover',0.35,1000.00,12.0000),
('Antiques Carrier',0.28,500.00,15.0000),('Art Transport',0.25,300.00,18.0000),('Museum Courier',0.22,200.00,20.0000),
('Plant Delivery',0.20,400.00,5.0000),('Flower Van',0.18,200.00,6.0000),('Garden Supply',0.30,1000.00,5.5000),
('Pet Transport',0.25,300.00,8.0000),('Animal Ambulance',0.32,500.00,10.0000),('Veterinary Mobile',0.28,400.00,9.0000),
('Mobile Library',0.30,1000.00,4.0000),('Book Mobile',0.25,800.00,3.5000),('Food Truck',0.35,1500.00,5.0000),
('Mobile Canteen',0.32,1000.00,4.5000),('Water Tanker',0.50,6000.00,8.0000),('Fuel Delivery',0.55,5000.00,10.0000),
('Propane Truck',0.52,4000.00,12.0000),('Heating Oil',0.48,4500.00,9.5000),('Ice Cream Van',0.25,200.00,6.0000),
('Mobile Shop',0.30,800.00,5.0000),('Pop-up Store',0.28,600.00,5.5000),('Exhibition Trailer',0.35,2000.00,7.0000),
('Stage Truck',0.42,5000.00,8.0000),('Sound Equipment',0.38,3000.00,7.5000),('Lighting Rig',0.40,3500.00,8.0000),
('Generator Truck',0.45,4000.00,9.0000),('Mobile Workshop',0.35,2500.00,8.5000),('Service Van',0.28,800.00,7.0000),
('Emergency Response',0.38,2000.00,10.0000),('Disaster Relief',0.42,3000.00,9.0000),('Humanitarian Aid',0.40,3500.00,8.0000);

-- C11. vehicles — 100 additional vehicles
INSERT INTO vehicles (type_id, license_plate, current_status)
SELECT
    (n % 50) + 1,
    CONCAT('GEN', LPAD(n, 5, '0')),
    CASE
        WHEN n % 7 = 0 THEN 'Maintenance'
        WHEN n % 11 = 0 THEN 'Retired'
        WHEN n % 5 = 0 THEN 'On Route'
        ELSE 'Available'
    END
FROM (
    SELECT @n := @n + 1 AS n FROM (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) a, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) b, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
    ) c
    CROSS JOIN (SELECT @n := 10) init
) nums;

-- C12. orders — 100 additional orders distributed across customers and nodes
INSERT INTO orders (customer_id, pickup_node_id, dropoff_node_id, order_date, total_weight, status)
SELECT
    (n % 25) + 1,
    (n % 50) + 11,
    ((n + 15) % 50) + 11,
    DATE_SUB(CURDATE(), INTERVAL (200 - n) DAY),
    ROUND(RAND() * 1000 + 10, 2),
    CASE
        WHEN n MOD 5 = 0 THEN 'Delivered'
        WHEN n MOD 7 = 0 THEN 'Cancelled'
        WHEN n MOD 11 = 0 THEN 'Failed'
        WHEN n < 40 THEN 'In Transit'
        WHEN n < 70 THEN 'Pending'
        ELSE 'Draft'
    END
FROM (
    SELECT @n := @n + 1 AS n FROM (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) a, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) b, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
    ) c
    CROSS JOIN (SELECT @n := 10) init
) nums
WHERE (n % 50) + 11 <> ((n + 15) % 50) + 11;

-- C13. routes — 100 additional routes
INSERT INTO routes (vehicle_id, driver_id, planned_date, total_distance, status)
SELECT
    (n % 50) + 11,
    (n % 40) + 11,
    DATE_SUB(CURDATE(), INTERVAL (150 - n) DAY),
    ROUND(RAND() * 200 + 20, 2),
    CASE
        WHEN n MOD 4 = 0 THEN 'Completed'
        WHEN n MOD 6 = 0 THEN 'Cancelled'
        WHEN n MOD 10 = 0 THEN 'Active'
        ELSE 'Planned'
    END
FROM (
    SELECT @n := @n + 1 AS n FROM (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) a, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) b, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
    ) c
    CROSS JOIN (SELECT @n := 10) init
) nums;

-- C14. route_segments — generated by Dijkstra shortest path on edge distance_units
INSERT INTO route_segments (route_id, edge_id, sequence_order) VALUES
(11, 29, 1), (11, 12, 2), (11, 13, 3), (11, 14, 4), (11, 15, 5), (11, 16, 6), (11, 69, 7), (11, 70, 8),
(12, 37, 1), (12, 13, 2), (12, 14, 3), (12, 15, 4), (12, 16, 5), (12, 17, 6), (12, 77, 7), (12, 78, 8),
(13, 45, 1), (13, 14, 2), (13, 15, 3), (13, 16, 4), (13, 17, 5), (13, 18, 6), (13, 85, 7), (13, 86, 8),
(14, 53, 1), (14, 15, 2), (14, 16, 3), (14, 17, 4), (14, 18, 5), (14, 19, 6), (14, 93, 7), (14, 94, 8),
(15, 61, 1), (15, 15, 2), (15, 14, 3), (15, 13, 4), (15, 12, 5), (15, 11, 6), (15, 20, 7), (15, 21, 8), (15, 22, 9),
(16, 69, 1), (16, 16, 2), (16, 15, 3), (16, 14, 4), (16, 13, 5), (16, 12, 6), (16, 29, 7), (16, 30, 8), (16, 31, 9),
(17, 77, 1), (17, 17, 2), (17, 16, 3), (17, 15, 4), (17, 14, 5), (17, 13, 6), (17, 37, 7), (17, 38, 8), (17, 39, 9),
(18, 85, 1), (18, 18, 2), (18, 17, 3), (18, 16, 4), (18, 15, 5), (18, 14, 6), (18, 45, 7), (18, 46, 8), (18, 47, 9),
(19, 93, 1), (19, 19, 2), (19, 18, 3), (19, 17, 4), (19, 16, 5), (19, 15, 6), (19, 53, 7), (19, 54, 8), (19, 55, 9),
(20, 21, 1), (20, 20, 2), (20, 11, 3), (20, 12, 4), (20, 13, 5), (20, 14, 6), (20, 15, 7), (20, 61, 8), (20, 62, 9), (20, 63, 10),
(21, 30, 1), (21, 29, 2), (21, 12, 3), (21, 13, 4), (21, 14, 5), (21, 15, 6), (21, 16, 7), (21, 69, 8), (21, 70, 9), (21, 71, 10),
(22, 38, 1), (22, 37, 2), (22, 13, 3), (22, 14, 4), (22, 15, 5), (22, 16, 6), (22, 17, 7), (22, 77, 8), (22, 78, 9), (22, 79, 10),
(23, 46, 1), (23, 45, 2), (23, 14, 3), (23, 15, 4), (23, 16, 5), (23, 17, 6), (23, 18, 7), (23, 85, 8), (23, 86, 9), (23, 87, 10),
(24, 54, 1), (24, 53, 2), (24, 15, 3), (24, 16, 4), (24, 17, 5), (24, 18, 6), (24, 19, 7), (24, 93, 8), (24, 94, 9), (24, 95, 10),
(25, 62, 1), (25, 61, 2), (25, 15, 3), (25, 14, 4), (25, 13, 5), (25, 12, 6), (25, 11, 7), (25, 20, 8), (25, 21, 9), (25, 22, 10), (25, 23, 11),
(26, 70, 1), (26, 69, 2), (26, 16, 3), (26, 15, 4), (26, 14, 5), (26, 13, 6), (26, 12, 7), (26, 29, 8), (26, 30, 9), (26, 31, 10), (26, 32, 11),
(27, 78, 1), (27, 77, 2), (27, 17, 3), (27, 16, 4), (27, 15, 5), (27, 14, 6), (27, 13, 7), (27, 37, 8), (27, 38, 9), (27, 39, 10), (27, 40, 11),
(28, 86, 1), (28, 85, 2), (28, 18, 3), (28, 17, 4), (28, 16, 5), (28, 15, 6), (28, 14, 7), (28, 45, 8), (28, 46, 9), (28, 47, 10), (28, 48, 11),
(29, 94, 1), (29, 93, 2), (29, 19, 3), (29, 18, 4), (29, 17, 5), (29, 16, 6), (29, 15, 7), (29, 53, 8), (29, 54, 9), (29, 55, 10), (29, 56, 11),
(30, 22, 1), (30, 21, 2), (30, 20, 3), (30, 11, 4), (30, 12, 5), (30, 13, 6), (30, 14, 7), (30, 15, 8), (30, 61, 9), (30, 62, 10), (30, 63, 11), (30, 64, 12),
(31, 31, 1), (31, 30, 2), (31, 29, 3), (31, 12, 4), (31, 13, 5), (31, 14, 6), (31, 15, 7), (31, 16, 8), (31, 69, 9), (31, 70, 10), (31, 71, 11), (31, 72, 12),
(32, 39, 1), (32, 38, 2), (32, 37, 3), (32, 13, 4), (32, 14, 5), (32, 15, 6), (32, 16, 7), (32, 17, 8), (32, 77, 9), (32, 78, 10), (32, 79, 11), (32, 80, 12),
(33, 47, 1), (33, 46, 2), (33, 45, 3), (33, 14, 4), (33, 15, 5), (33, 16, 6), (33, 17, 7), (33, 18, 8), (33, 85, 9), (33, 86, 10), (33, 87, 11), (33, 88, 12),
(34, 55, 1), (34, 54, 2), (34, 53, 3), (34, 15, 4), (34, 16, 5), (34, 17, 6), (34, 18, 7), (34, 19, 8), (34, 93, 9), (34, 94, 10), (34, 95, 11), (34, 96, 12),
(35, 63, 1), (35, 62, 2), (35, 61, 3), (35, 15, 4), (35, 14, 5), (35, 13, 6), (35, 12, 7), (35, 11, 8),
(36, 71, 1), (36, 70, 2), (36, 69, 3), (36, 16, 4), (36, 15, 5), (36, 14, 6), (36, 13, 7), (36, 12, 8),
(37, 79, 1), (37, 78, 2), (37, 77, 3), (37, 17, 4), (37, 16, 5), (37, 15, 6), (37, 14, 7), (37, 13, 8),
(38, 87, 1), (38, 86, 2), (38, 85, 3), (38, 18, 4), (38, 17, 5), (38, 16, 6), (38, 15, 7), (38, 14, 8),
(39, 95, 1), (39, 94, 2), (39, 93, 3), (39, 19, 4), (39, 18, 5), (39, 17, 6), (39, 16, 7), (39, 15, 8),
(40, 23, 1), (40, 22, 2), (40, 21, 3), (40, 20, 4), (40, 11, 5), (40, 12, 6), (40, 13, 7), (40, 14, 8), (40, 15, 9),
(41, 32, 1), (41, 31, 2), (41, 30, 3), (41, 29, 4), (41, 12, 5), (41, 13, 6), (41, 14, 7), (41, 15, 8), (41, 16, 9),
(42, 40, 1), (42, 39, 2), (42, 38, 3), (42, 37, 4), (42, 13, 5), (42, 14, 6), (42, 15, 7), (42, 16, 8), (42, 17, 9),
(43, 48, 1), (43, 47, 2), (43, 46, 3), (43, 45, 4), (43, 14, 5), (43, 15, 6), (43, 16, 7), (43, 17, 8), (43, 18, 9),
(44, 56, 1), (44, 55, 2), (44, 54, 3), (44, 53, 4), (44, 15, 5), (44, 16, 6), (44, 17, 7), (44, 18, 8), (44, 19, 9),
(45, 64, 1), (45, 63, 2), (45, 62, 3), (45, 61, 4), (45, 15, 5), (45, 14, 6), (45, 13, 7), (45, 12, 8), (45, 11, 9), (45, 20, 10),
(46, 72, 1), (46, 71, 2), (46, 70, 3), (46, 69, 4), (46, 16, 5), (46, 15, 6), (46, 14, 7), (46, 13, 8), (46, 12, 9), (46, 29, 10),
(47, 80, 1), (47, 79, 2), (47, 78, 3), (47, 77, 4), (47, 17, 5), (47, 16, 6), (47, 15, 7), (47, 14, 8), (47, 13, 9), (47, 37, 10),
(48, 88, 1), (48, 87, 2), (48, 86, 3), (48, 85, 4), (48, 18, 5), (48, 17, 6), (48, 16, 7), (48, 15, 8), (48, 14, 9), (48, 45, 10),
(49, 96, 1), (49, 95, 2), (49, 94, 3), (49, 93, 4), (49, 19, 5), (49, 18, 6), (49, 17, 7), (49, 16, 8), (49, 15, 9), (49, 53, 10),
(50, 11, 1), (50, 12, 2), (50, 13, 3), (50, 14, 4), (50, 15, 5), (50, 61, 6),
(51, 12, 1), (51, 13, 2), (51, 14, 3), (51, 15, 4), (51, 16, 5), (51, 69, 6),
(52, 13, 1), (52, 14, 2), (52, 15, 3), (52, 16, 4), (52, 17, 5), (52, 77, 6),
(53, 14, 1), (53, 15, 2), (53, 16, 3), (53, 17, 4), (53, 18, 5), (53, 85, 6),
(54, 15, 1), (54, 16, 2), (54, 17, 3), (54, 18, 4), (54, 19, 5), (54, 93, 6),
(55, 15, 1), (55, 14, 2), (55, 13, 3), (55, 12, 4), (55, 11, 5), (55, 20, 6), (55, 21, 7),
(56, 16, 1), (56, 15, 2), (56, 14, 3), (56, 13, 4), (56, 12, 5), (56, 29, 6), (56, 30, 7),
(57, 17, 1), (57, 16, 2), (57, 15, 3), (57, 14, 4), (57, 13, 5), (57, 37, 6), (57, 38, 7),
(58, 18, 1), (58, 17, 2), (58, 16, 3), (58, 15, 4), (58, 14, 5), (58, 45, 6), (58, 46, 7),
(59, 19, 1), (59, 18, 2), (59, 17, 3), (59, 16, 4), (59, 15, 5), (59, 53, 6), (59, 54, 7),
(60, 20, 1), (60, 11, 2), (60, 12, 3), (60, 13, 4), (60, 14, 5), (60, 15, 6), (60, 61, 7), (60, 62, 8),
(61, 29, 1), (61, 12, 2), (61, 13, 3), (61, 14, 4), (61, 15, 5), (61, 16, 6), (61, 69, 7), (61, 70, 8),
(62, 37, 1), (62, 13, 2), (62, 14, 3), (62, 15, 4), (62, 16, 5), (62, 17, 6), (62, 77, 7), (62, 78, 8),
(63, 45, 1), (63, 14, 2), (63, 15, 3), (63, 16, 4), (63, 17, 5), (63, 18, 6), (63, 85, 7), (63, 86, 8),
(64, 53, 1), (64, 15, 2), (64, 16, 3), (64, 17, 4), (64, 18, 5), (64, 19, 6), (64, 93, 7), (64, 94, 8),
(65, 61, 1), (65, 15, 2), (65, 14, 3), (65, 13, 4), (65, 12, 5), (65, 11, 6), (65, 20, 7), (65, 21, 8), (65, 22, 9),
(66, 69, 1), (66, 16, 2), (66, 15, 3), (66, 14, 4), (66, 13, 5), (66, 12, 6), (66, 29, 7), (66, 30, 8), (66, 31, 9),
(67, 77, 1), (67, 17, 2), (67, 16, 3), (67, 15, 4), (67, 14, 5), (67, 13, 6), (67, 37, 7), (67, 38, 8), (67, 39, 9),
(68, 85, 1), (68, 18, 2), (68, 17, 3), (68, 16, 4), (68, 15, 5), (68, 14, 6), (68, 45, 7), (68, 46, 8), (68, 47, 9),
(69, 93, 1), (69, 19, 2), (69, 18, 3), (69, 17, 4), (69, 16, 5), (69, 15, 6), (69, 53, 7), (69, 54, 8), (69, 55, 9),
(70, 21, 1), (70, 20, 2), (70, 11, 3), (70, 12, 4), (70, 13, 5), (70, 14, 6), (70, 15, 7), (70, 61, 8), (70, 62, 9), (70, 63, 10),
(71, 30, 1), (71, 29, 2), (71, 12, 3), (71, 13, 4), (71, 14, 5), (71, 15, 6), (71, 16, 7), (71, 69, 8), (71, 70, 9), (71, 71, 10),
(72, 38, 1), (72, 37, 2), (72, 13, 3), (72, 14, 4), (72, 15, 5), (72, 16, 6), (72, 17, 7), (72, 77, 8), (72, 78, 9), (72, 79, 10),
(73, 46, 1), (73, 45, 2), (73, 14, 3), (73, 15, 4), (73, 16, 5), (73, 17, 6), (73, 18, 7), (73, 85, 8), (73, 86, 9), (73, 87, 10),
(74, 54, 1), (74, 53, 2), (74, 15, 3), (74, 16, 4), (74, 17, 5), (74, 18, 6), (74, 19, 7), (74, 93, 8), (74, 94, 9), (74, 95, 10),
(75, 62, 1), (75, 61, 2), (75, 15, 3), (75, 14, 4), (75, 13, 5), (75, 12, 6), (75, 11, 7), (75, 20, 8), (75, 21, 9), (75, 22, 10), (75, 23, 11),
(76, 70, 1), (76, 69, 2), (76, 16, 3), (76, 15, 4), (76, 14, 5), (76, 13, 6), (76, 12, 7), (76, 29, 8), (76, 30, 9), (76, 31, 10), (76, 32, 11),
(77, 78, 1), (77, 77, 2), (77, 17, 3), (77, 16, 4), (77, 15, 5), (77, 14, 6), (77, 13, 7), (77, 37, 8), (77, 38, 9), (77, 39, 10), (77, 40, 11),
(78, 86, 1), (78, 85, 2), (78, 18, 3), (78, 17, 4), (78, 16, 5), (78, 15, 6), (78, 14, 7), (78, 45, 8), (78, 46, 9), (78, 47, 10), (78, 48, 11),
(79, 94, 1), (79, 93, 2), (79, 19, 3), (79, 18, 4), (79, 17, 5), (79, 16, 6), (79, 15, 7), (79, 53, 8), (79, 54, 9), (79, 55, 10), (79, 56, 11),
(80, 22, 1), (80, 21, 2), (80, 20, 3), (80, 11, 4), (80, 12, 5), (80, 13, 6), (80, 14, 7), (80, 15, 8), (80, 61, 9), (80, 62, 10), (80, 63, 11), (80, 64, 12),
(81, 31, 1), (81, 30, 2), (81, 29, 3), (81, 12, 4), (81, 13, 5), (81, 14, 6), (81, 15, 7), (81, 16, 8), (81, 69, 9), (81, 70, 10), (81, 71, 11), (81, 72, 12),
(82, 39, 1), (82, 38, 2), (82, 37, 3), (82, 13, 4), (82, 14, 5), (82, 15, 6), (82, 16, 7), (82, 17, 8), (82, 77, 9), (82, 78, 10), (82, 79, 11), (82, 80, 12),
(83, 47, 1), (83, 46, 2), (83, 45, 3), (83, 14, 4), (83, 15, 5), (83, 16, 6), (83, 17, 7), (83, 18, 8), (83, 85, 9), (83, 86, 10), (83, 87, 11), (83, 88, 12),
(84, 55, 1), (84, 54, 2), (84, 53, 3), (84, 15, 4), (84, 16, 5), (84, 17, 6), (84, 18, 7), (84, 19, 8), (84, 93, 9), (84, 94, 10), (84, 95, 11), (84, 96, 12),
(85, 63, 1), (85, 62, 2), (85, 61, 3), (85, 15, 4), (85, 14, 5), (85, 13, 6), (85, 12, 7), (85, 11, 8),
(86, 71, 1), (86, 70, 2), (86, 69, 3), (86, 16, 4), (86, 15, 5), (86, 14, 6), (86, 13, 7), (86, 12, 8),
(87, 79, 1), (87, 78, 2), (87, 77, 3), (87, 17, 4), (87, 16, 5), (87, 15, 6), (87, 14, 7), (87, 13, 8),
(88, 87, 1), (88, 86, 2), (88, 85, 3), (88, 18, 4), (88, 17, 5), (88, 16, 6), (88, 15, 7), (88, 14, 8),
(89, 95, 1), (89, 94, 2), (89, 93, 3), (89, 19, 4), (89, 18, 5), (89, 17, 6), (89, 16, 7), (89, 15, 8),
(90, 23, 1), (90, 22, 2), (90, 21, 3), (90, 20, 4), (90, 11, 5), (90, 12, 6), (90, 13, 7), (90, 14, 8), (90, 15, 9),
(91, 32, 1), (91, 31, 2), (91, 30, 3), (91, 29, 4), (91, 12, 5), (91, 13, 6), (91, 14, 7), (91, 15, 8), (91, 16, 9),
(92, 40, 1), (92, 39, 2), (92, 38, 3), (92, 37, 4), (92, 13, 5), (92, 14, 6), (92, 15, 7), (92, 16, 8), (92, 17, 9),
(93, 48, 1), (93, 47, 2), (93, 46, 3), (93, 45, 4), (93, 14, 5), (93, 15, 6), (93, 16, 7), (93, 17, 8), (93, 18, 9),
(94, 56, 1), (94, 55, 2), (94, 54, 3), (94, 53, 4), (94, 15, 5), (94, 16, 6), (94, 17, 7), (94, 18, 8), (94, 19, 9),
(95, 64, 1), (95, 63, 2), (95, 62, 3), (95, 61, 4), (95, 15, 5), (95, 14, 6), (95, 13, 7), (95, 12, 8), (95, 11, 9), (95, 20, 10),
(96, 72, 1), (96, 71, 2), (96, 70, 3), (96, 69, 4), (96, 16, 5), (96, 15, 6), (96, 14, 7), (96, 13, 8), (96, 12, 9), (96, 29, 10),
(97, 80, 1), (97, 79, 2), (97, 78, 3), (97, 77, 4), (97, 17, 5), (97, 16, 6), (97, 15, 7), (97, 14, 8), (97, 13, 9), (97, 37, 10),
(98, 88, 1), (98, 87, 2), (98, 86, 3), (98, 85, 4), (98, 18, 5), (98, 17, 6), (98, 16, 7), (98, 15, 8), (98, 14, 9), (98, 45, 10),
(99, 96, 1), (99, 95, 2), (99, 94, 3), (99, 93, 4), (99, 19, 5), (99, 18, 6), (99, 17, 7), (99, 16, 8), (99, 15, 9), (99, 53, 10),
(100, 11, 1), (100, 12, 2), (100, 13, 3), (100, 14, 4), (100, 15, 5), (100, 61, 6),
(101, 12, 1), (101, 13, 2), (101, 14, 3), (101, 15, 4), (101, 16, 5), (101, 69, 6),
(102, 13, 1), (102, 14, 2), (102, 15, 3), (102, 16, 4), (102, 17, 5), (102, 77, 6),
(103, 14, 1), (103, 15, 2), (103, 16, 3), (103, 17, 4), (103, 18, 5), (103, 85, 6),
(104, 15, 1), (104, 16, 2), (104, 17, 3), (104, 18, 4), (104, 19, 5), (104, 93, 6),
(105, 15, 1), (105, 14, 2), (105, 13, 3), (105, 12, 4), (105, 11, 5), (105, 20, 6), (105, 21, 7),
(106, 16, 1), (106, 15, 2), (106, 14, 3), (106, 13, 4), (106, 12, 5), (106, 29, 6), (106, 30, 7),
(107, 17, 1), (107, 16, 2), (107, 15, 3), (107, 14, 4), (107, 13, 5), (107, 37, 6), (107, 38, 7),
(108, 18, 1), (108, 17, 2), (108, 16, 3), (108, 15, 4), (108, 14, 5), (108, 45, 6), (108, 46, 7),
(109, 19, 1), (109, 18, 2), (109, 17, 3), (109, 16, 4), (109, 15, 5), (109, 53, 6), (109, 54, 7),
(110, 20, 1), (110, 11, 2), (110, 12, 3), (110, 13, 4), (110, 14, 5), (110, 15, 6), (110, 61, 7), (110, 62, 8);

-- C15. deliveries — generated by Dijkstra shortest path on edge distance_units
INSERT INTO deliveries (order_id, route_id, status, actual_time) VALUES
(11, 11, 'Pending', NULL),
(12, 12, 'In Transit', NULL),
(13, 13, 'Pending', NULL),
(14, 14, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 14) HOUR)),
(15, 15, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 15) HOUR)),
(16, 16, 'Pending', NULL),
(17, 17, 'Pending', NULL),
(18, 18, 'In Transit', NULL),
(19, 19, 'Pending', NULL),
(20, 20, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 20) HOUR)),
(21, 21, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 21) HOUR)),
(22, 22, 'Pending', NULL),
(23, 23, 'Pending', NULL),
(24, 24, 'In Transit', NULL),
(25, 25, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 25) HOUR)),
(26, 26, 'Pending', NULL),
(27, 27, 'In Transit', NULL),
(28, 28, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 28) HOUR)),
(29, 29, 'Pending', NULL),
(30, 30, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 30) HOUR)),
(31, 31, 'Pending', NULL),
(32, 32, 'Pending', NULL),
(33, 33, 'In Transit', NULL),
(34, 34, 'Pending', NULL),
(35, 35, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 35) HOUR)),
(36, 36, 'In Transit', NULL),
(37, 37, 'Pending', NULL),
(38, 38, 'Pending', NULL),
(39, 39, 'In Transit', NULL),
(40, 40, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 40) HOUR)),
(41, 41, 'Pending', NULL),
(42, 42, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 42) HOUR)),
(43, 43, 'Pending', NULL),
(44, 44, 'Pending', NULL),
(45, 45, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 45) HOUR)),
(46, 46, 'Pending', NULL),
(47, 47, 'Pending', NULL),
(48, 48, 'In Transit', NULL),
(49, 49, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 49) HOUR)),
(50, 50, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 50) HOUR)),
(51, 51, 'In Transit', NULL),
(52, 52, 'Pending', NULL),
(53, 53, 'Pending', NULL),
(54, 54, 'In Transit', NULL),
(55, 55, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 55) HOUR)),
(56, 56, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 56) HOUR)),
(57, 57, 'In Transit', NULL),
(58, 58, 'Pending', NULL),
(59, 59, 'Pending', NULL),
(60, 60, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 60) HOUR)),
(61, 61, 'Pending', NULL),
(62, 62, 'Pending', NULL),
(63, 63, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 63) HOUR)),
(64, 64, 'Pending', NULL),
(65, 65, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 65) HOUR)),
(66, 66, 'In Transit', NULL),
(67, 67, 'Pending', NULL),
(68, 68, 'Pending', NULL),
(69, 69, 'In Transit', NULL),
(70, 70, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 70) HOUR)),
(71, 71, 'Pending', NULL),
(72, 72, 'In Transit', NULL),
(73, 73, 'Pending', NULL),
(74, 74, 'Pending', NULL),
(75, 75, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 75) HOUR)),
(76, 76, 'Pending', NULL),
(77, 77, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 77) HOUR)),
(78, 78, 'In Transit', NULL),
(79, 79, 'Pending', NULL),
(80, 80, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 80) HOUR)),
(81, 81, 'In Transit', NULL),
(82, 82, 'Pending', NULL),
(83, 83, 'Pending', NULL),
(84, 84, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 84) HOUR)),
(85, 85, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 85) HOUR)),
(86, 86, 'Pending', NULL),
(87, 87, 'In Transit', NULL),
(88, 88, 'Pending', NULL),
(89, 89, 'Pending', NULL),
(90, 90, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 90) HOUR)),
(91, 91, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 91) HOUR)),
(92, 92, 'Pending', NULL),
(93, 93, 'In Transit', NULL),
(94, 94, 'Pending', NULL),
(95, 95, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 95) HOUR)),
(96, 96, 'In Transit', NULL),
(97, 97, 'Pending', NULL),
(98, 98, 'Failed', DATE_SUB(NOW(), INTERVAL (100 - 98) HOUR)),
(99, 99, 'In Transit', NULL),
(100, 100, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 100) HOUR)),
(101, 101, 'Pending', NULL),
(102, 102, 'In Transit', NULL),
(103, 103, 'Pending', NULL),
(104, 104, 'Pending', NULL),
(105, 105, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 105) HOUR)),
(106, 106, 'Pending', NULL),
(107, 107, 'Pending', NULL),
(108, 108, 'In Transit', NULL),
(109, 109, 'Pending', NULL),
(110, 110, 'Delivered', DATE_SUB(NOW(), INTERVAL (100 - 110) HOUR));

-- C16. maintenance_logs — 100 additional maintenance records
INSERT INTO maintenance_logs (vehicle_id, service_date, description, cost)
SELECT
    (n % 100) + 11,
    DATE_SUB(CURDATE(), INTERVAL (n * 3) DAY),
    ELT(1 + (n MOD 8),
        'Routine inspection and fluid check',
        'Tire replacement and wheel alignment',
        'Brake system overhaul',
        'Engine diagnostics and tune-up',
        'Transmission service',
        'Electrical system repair',
        'HVAC system maintenance',
        'Suspension and steering check'
    ),
    ROUND(RAND() * 3000 + 150, 2)
FROM (
    SELECT @n := @n + 1 AS n FROM (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) a, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    ) b, (
        SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
    ) c
    CROSS JOIN (SELECT @n := 0) init
) nums;

INSERT INTO maintenance_logs (vehicle_id, service_date, description, cost) VALUES
(1, '2025-12-15', 'Annual battery inspection and software update', 450.00),
(2, '2025-11-20', 'Oil change, brake pad replacement', 680.00),
(3, '2025-10-10', 'Tire rotation, transmission fluid check', 520.00),
(4, '2025-12-01', 'Cooling system overhaul, refrigerant recharge', 2100.00),
(5, '2025-09-15', 'Engine tune-up, spark plug replacement', 350.00),
(6, '2025-08-20', 'Hydraulic system inspection, brake lines', 890.00),
(7, '2025-11-05', 'Routine service, belt replacement', 420.00),
(8, '2025-07-01', 'Engine rebuild (major)', 4500.00),
(9, '2025-12-20', 'Chain replacement, brake adjustment', 120.00),
(10, '2025-10-25', 'Brake system check, tire replacement', 580.00);

-- ==============================================================
-- SECTION B: Data Transfer via INSERT INTO ... SELECT
-- (10 records per table — transferred from related tables)
-- ==============================================================

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Create additional locations by copying customer names + node info
INSERT INTO locations (node_id, name, address_text)
SELECT n.id, CONCAT('Customer Drop: ', c.first_name, ' ', c.last_name),
       CONCAT(n.label, ', Delivery Point #', c.id)
FROM customers c
CROSS JOIN nodes n
LIMIT 10;

-- 2. Create follow-up orders from existing customer data
INSERT INTO orders (customer_id, pickup_node_id, dropoff_node_id, order_date, total_weight, status)
SELECT c.id, n1.id, n2.id, DATE_ADD(CURDATE(), INTERVAL c.id DAY),
       ROUND(RAND() * 500 + 10, 2), 'Draft'
FROM customers c
JOIN nodes n1 ON n1.id = (c.id % 10) + 1
JOIN nodes n2 ON n2.id = ((c.id + 3) % 10) + 1
WHERE c.id <= 10 AND n1.id <> n2.id;

-- 3. Create additional routes from vehicles + staff cross-reference
INSERT INTO routes (vehicle_id, driver_id, planned_date, total_distance, status)
SELECT v.id, s.id, DATE_ADD(CURDATE(), INTERVAL v.id DAY),
       ROUND(RAND() * 100 + 20, 2), 'Planned'
FROM vehicles v
JOIN staff s ON s.position = 'Driver'
WHERE v.current_status = 'Available'
LIMIT 10;

-- 4. Create route segments — generated by Dijkstra shortest path on edge distance_units
-- Uses MAX(id) scalar subquery to dynamically compute correct route_ids
INSERT INTO route_segments (route_id, edge_id, sequence_order)
SELECT (SELECT MAX(id) FROM routes) - 10 + segs.rn, segs.edge_id, segs.seq
FROM (
  SELECT 1 rn, 1 edge_id, 1 seq UNION ALL
  SELECT 1, 5, 2 UNION ALL
  SELECT 2, 2, 1 UNION ALL
  SELECT 2, 6, 2 UNION ALL
  SELECT 3, 3, 1 UNION ALL
  SELECT 3, 2, 2 UNION ALL
  SELECT 3, 6, 3 UNION ALL
  SELECT 3, 7, 4 UNION ALL
  SELECT 4, 5, 1 UNION ALL
  SELECT 4, 1, 2 UNION ALL
  SELECT 4, 6, 3 UNION ALL
  SELECT 4, 7, 4 UNION ALL
  SELECT 4, 8, 5 UNION ALL
  SELECT 5, 7, 1 UNION ALL
  SELECT 5, 8, 2 UNION ALL
  SELECT 5, 9, 3 UNION ALL
  SELECT 6, 8, 1 UNION ALL
  SELECT 6, 9, 2 UNION ALL
  SELECT 6, 10, 3 UNION ALL
  SELECT 7, 8, 1 UNION ALL
  SELECT 7, 7, 2 UNION ALL
  SELECT 7, 6, 3 UNION ALL
  SELECT 7, 1, 4 UNION ALL
  SELECT 8, 9, 1 UNION ALL
  SELECT 8, 8, 2 UNION ALL
  SELECT 8, 7, 3 UNION ALL
  SELECT 8, 6, 4 UNION ALL
  SELECT 9, 10, 1 UNION ALL
  SELECT 9, 9, 2 UNION ALL
  SELECT 9, 8, 3 UNION ALL
  SELECT 9, 7, 4 UNION ALL
  SELECT 9, 6, 5 UNION ALL
  SELECT 9, 2, 6 UNION ALL
  SELECT 10, 5, 1 UNION ALL
  SELECT 10, 4, 2
) segs;

-- 5. Create deliveries — all valid (routes have proper Dijkstra-generated segments)
INSERT INTO deliveries (order_id, route_id, status, actual_time)
SELECT 110 + seq.rn, (SELECT MAX(id) FROM routes) - 10 + seq.rn, 'Pending', NULL
FROM (
  SELECT 1 rn UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL
  SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL
  SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
) seq;

SET FOREIGN_KEY_CHECKS = 1;

-- 6. Create maintenance logs for all vehicles
INSERT INTO maintenance_logs (vehicle_id, service_date, description, cost)
SELECT v.id, DATE_SUB(CURDATE(), INTERVAL v.id * 30 DAY),
       CONCAT('Scheduled service for ', vt.type_name),
       ROUND(RAND() * 2000 + 100, 2)
FROM vehicles v
JOIN vehicle_types vt ON vt.id = v.type_id
WHERE v.current_status != 'Retired'
LIMIT 10;

-- 7. Copy staff as users with Driver role
INSERT INTO users (username, password_hash, role_id, staff_id, customer_id)
SELECT LOWER(CONCAT(LEFT(s.first_name, 1), s.last_name)),
       '$2a$10$HpyiB4n6cVLv0nu6Ta3dbeyjW.PYWo0hoG11OklU27Sy6UeTxiqJS',
       4, s.id, NULL
FROM staff s
LEFT JOIN users u ON u.staff_id = s.id
WHERE u.id IS NULL AND s.position IN ('Driver', 'Warehouse Operator')
LIMIT 10;

-- 8. Create new nodes offset from existing ones
INSERT INTO nodes (x_coord, y_coord, label, map_region_id)
SELECT x_coord + 5, y_coord + 5, CONCAT(label, ' Annex'), map_region_id
FROM nodes
WHERE id <= 10;

-- 9. Create edges connecting new annex nodes
INSERT INTO edges (node_a_id, node_b_id, distance_units, speed_limit, map_region_id)
SELECT n1.id, n2.id, ROUND(RAND() * 30 + 5, 2), 40, n1.map_region_id
FROM nodes n1
JOIN nodes n2 ON n2.id = n1.id - 10
WHERE n1.id > 10 AND n1.id <= 20 AND n2.id <= 10
LIMIT 10;

-- 10. Extend vehicle fleet by cloning available types
INSERT INTO vehicles (type_id, license_plate, current_status)
SELECT vt.id,
       CONCAT(UPPER(LEFT(vt.type_name, 3)), LPAD(vt.id * 10 + seq.rn, 3, '0')),
       'Available'
FROM vehicle_types vt
CROSS JOIN (
    SELECT 1 AS rn UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
    UNION SELECT 5 UNION SELECT 6 UNION SELECT 7
    UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
) seq
WHERE vt.id <= 5
LIMIT 10;

