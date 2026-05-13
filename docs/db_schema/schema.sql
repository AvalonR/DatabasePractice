CREATE DATABASE IF NOT EXISTS delivery_system;
USE delivery_system;

-- 1. Nodes (Coordinate points for the imaginary map)
CREATE TABLE nodes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    x_coord DECIMAL(10, 2) NOT NULL,
    y_coord DECIMAL(10, 2) NOT NULL,
    label VARCHAR(100)
);

-- 2. Edges (The 'Roads' connecting nodes)
CREATE TABLE edges (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_a_id INT,
    node_b_id INT,
    distance_units DECIMAL(10, 2),
    speed_limit INT DEFAULT 50,
    FOREIGN KEY (node_a_id) REFERENCES nodes(id),
    FOREIGN KEY (node_b_id) REFERENCES nodes(id)
);

-- 3. Locations (Specific hubs or client sites linked to nodes)
CREATE TABLE locations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT,
    name VARCHAR(150) NOT NULL,
    address_text VARCHAR(255),
    FOREIGN KEY (node_id) REFERENCES nodes(id)
);

-- 4. Customers (Standardized for professional addressing)
CREATE TABLE customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(20)
);

-- 5. Staff (Generic employees: Drivers, Managers, Officials)
CREATE TABLE staff (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    position VARCHAR(100), -- e.g., 'Driver', 'Regional Manager'
    hire_date DATE
);

-- 6. Permissions (Simplified but effective security)
CREATE TABLE permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    perm_key VARCHAR(50) UNIQUE NOT NULL -- e.g., 'edit_routes', 'manage_users'
);

-- 7. Roles
CREATE TABLE roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL
);

-- 8. Role_Permissions (Security bridge)
CREATE TABLE role_permissions (
    role_id INT,
    permission_id INT,
    PRIMARY KEY (role_id, permission_id),
    FOREIGN KEY (role_id) REFERENCES roles(id),
    FOREIGN KEY (permission_id) REFERENCES permissions(id)
);

-- 9. Users (The login table - can link to either Staff or Customers)
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role_id INT,
    staff_id INT NULL, -- For employees
    customer_id INT NULL, -- For customers accessing their portal
    FOREIGN KEY (role_id) REFERENCES roles(id),
    FOREIGN KEY (staff_id) REFERENCES staff(id),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- 10. Vehicle_Types
CREATE TABLE vehicle_types (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type_name VARCHAR(50),
    fuel_rate DECIMAL(5, 2), -- Fuel units per distance unit
    max_weight_capacity DECIMAL(10, 2)
);

-- 11. Vehicles (Includes 'Retired' status)
CREATE TABLE vehicles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type_id INT,
    license_plate VARCHAR(20) UNIQUE,
    current_status ENUM('Available', 'On Route', 'Maintenance', 'Retired'),
    FOREIGN KEY (type_id) REFERENCES vehicle_types(id)
);

-- 12. Orders (The request for delivery)
CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT,
    pickup_node_id INT,
    dropoff_node_id INT,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_weight DECIMAL(10, 2),
    status ENUM('Pending', 'In Transit', 'Delivered', 'Failed') DEFAULT 'Pending',
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (pickup_node_id) REFERENCES nodes(id),
    FOREIGN KEY (dropoff_node_id) REFERENCES nodes(id)
);

-- 13. Routes (The planned journey)
CREATE TABLE routes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id INT,
    driver_id INT, -- Links to staff.id
    planned_date DATE,
    total_distance DECIMAL(10, 2) DEFAULT 0,
    FOREIGN KEY (vehicle_id) REFERENCES vehicles(id),
    FOREIGN KEY (driver_id) REFERENCES staff(id)
);

-- 14. Route_Segments (Sequence of edges for the route)
CREATE TABLE route_segments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    route_id INT,
    edge_id INT,
    sequence_order INT,
    FOREIGN KEY (route_id) REFERENCES routes(id),
    FOREIGN KEY (edge_id) REFERENCES edges(id)
);

-- 15. Deliveries (The status of a specific order on a route)
CREATE TABLE deliveries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT,
    route_id INT,
    status ENUM('Pending', 'In Transit', 'Delivered', 'Failed'),
    actual_time DATETIME,
    FOREIGN KEY (order_id) REFERENCES orders(id),
    FOREIGN KEY (route_id) REFERENCES routes(id)
);

-- 16. Maintenance_Logs (Vehicle health history)
CREATE TABLE maintenance_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id INT,
    service_date DATE,
    description TEXT,
    cost DECIMAL(10, 2),
    FOREIGN KEY (vehicle_id) REFERENCES vehicles(id)
);

-- 17. System_Audit_Logs (Security tracking)
CREATE TABLE system_audit_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action_performed VARCHAR(255),
    action_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- 18. Map_Regions (New table for categorization and better queries)
CREATE TABLE map_regions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    region_name VARCHAR(100),
    risk_level ENUM('Low', 'Medium', 'High')
);

DELIMITER //

CREATE TRIGGER after_delivery_update
AFTER UPDATE ON deliveries
FOR EACH ROW
BEGIN
    -- Only log if the status has actually changed
    IF OLD.status <> NEW.status THEN
        INSERT INTO system_audit_logs (user_id, action_performed)
        VALUES (
            (SELECT id FROM users WHERE role_id = (SELECT id FROM roles WHERE role_name = 'Admin') LIMIT 1), 
            CONCAT('Delivery ID ', NEW.id, ' status changed from ', OLD.status, ' to ', NEW.status)
        );
    END IF;
END; //

DELIMITER ;