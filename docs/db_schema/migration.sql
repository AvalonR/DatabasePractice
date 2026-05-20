-- Migration: price_per_kg column + audit triggers
-- Safe to re-run: uses IF NOT EXISTS / DROP TRIGGER IF EXISTS throughout.

USE delivery_system;

-- ============================================================
-- 1. Add price_per_kg column to vehicle_types
-- ============================================================
SET @exists := (SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'delivery_system'
      AND TABLE_NAME = 'vehicle_types'
      AND COLUMN_NAME = 'price_per_kg');

SET @sql := IF(@exists = 0,
    'ALTER TABLE vehicle_types
        ADD COLUMN price_per_kg DECIMAL(10,4) NOT NULL DEFAULT 10.0000
        AFTER max_weight_capacity',
    'SELECT ''price_per_kg already exists'' AS status');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================================
-- 2. Update existing vehicle types with sensible price_per_kg
--    (only if they still have the default 10.0000)
-- ============================================================
UPDATE vehicle_types
SET price_per_kg = 8.5000
WHERE type_name = 'Light Electric Van'
  AND price_per_kg = 10.0000;

UPDATE vehicle_types
SET price_per_kg = 12.0000
WHERE type_name = 'Heavy Diesel Truck'
  AND price_per_kg = 10.0000;

-- ============================================================
-- 3. Replace triggers (safe to re-run)
-- ============================================================
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
