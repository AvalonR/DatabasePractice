package main

import (
	"database/sql"
	"db_practice_app/db"
	"errors"
	"fmt"
	"log"
	"time"

	"golang.org/x/crypto/bcrypt"
)

type UserDetail struct {
	ID            int          `json:"id"`
	Username      string       `json:"username"`
	RoleName      string       `json:"role_name"`
	Permissions   []string     `json:"permissions"`
	Profile       *UserProfile `json:"profile,omitempty"`
	Metrics       *UserMetrics `json:"metrics,omitempty"`
	RecentActions []AuditEntry `json:"recent_actions"`
}

type UserProfile struct {
	Type      string  `json:"type"` // "staff" | "customer"
	FirstName string  `json:"first_name"`
	LastName  string  `json:"last_name"`
	Position  *string `json:"position,omitempty"`
	HireDate  *string `json:"hire_date,omitempty"`
	Email     *string `json:"email,omitempty"`
	Phone     *string `json:"phone,omitempty"`
}

type UserMetrics struct {
	ActiveOrders     *int     `json:"active_orders,omitempty"`
	CompletedOrders  *int     `json:"completed_orders,omitempty"`
	FailedDeliveries *int     `json:"failed_deliveries,omitempty"`
	TotalOrders      *int     `json:"total_orders,omitempty"`
	PendingOrders    *int     `json:"pending_orders,omitempty"`
	DeliveredOrders  *int     `json:"delivered_orders,omitempty"`
	TotalWeight      *float64 `json:"total_weight,omitempty"`
	AuditLogCount    int      `json:"audit_log_count"`
	LastActionAt     *string  `json:"last_action_at,omitempty"`
}

type AuditEntry struct {
	ID        int    `json:"id"`
	Action    string `json:"action"`
	Timestamp string `json:"timestamp"`
}

type _userRow struct {
	db.User
	RoleName string
}

func (a *App) GetUsers() ([]UserDetail, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	rows, err := a.db.Query(`
		SELECT u.id, u.username, u.password_hash, u.role_id,
		       u.staff_id, u.customer_id,
		       r.role_name
		FROM users u
		JOIN roles r ON r.id = u.role_id
		ORDER BY u.id
	`)
	if err != nil {
		return nil, fmt.Errorf("query users: %w", err)
	}
	defer rows.Close()

	var userRows []_userRow
	var staffIDs, customerIDs []int

	for rows.Next() {
		var ur _userRow
		var sid, cid sql.NullInt64
		if err := rows.Scan(&ur.ID, &ur.Username, &ur.PasswordHash,
			&ur.RoleID, &sid, &cid, &ur.RoleName); err != nil {
			return nil, fmt.Errorf("scan user: %w", err)
		}
		if sid.Valid {
			v := int(sid.Int64)
			ur.StaffID = sid
			staffIDs = append(staffIDs, v)
		}
		if cid.Valid {
			v := int(cid.Int64)
			ur.CustomerID = cid
			customerIDs = append(customerIDs, v)
		}
		userRows = append(userRows, ur)
	}

	permRows, err := a.db.Query(`
		SELECT rp.role_id, p.perm_key
		FROM role_permissions rp
		JOIN permissions p ON p.id = rp.permission_id
	`)
	if err != nil {
		return nil, fmt.Errorf("query permissions: %w", err)
	}
	defer permRows.Close()

	rolePerms := map[int][]string{}
	for permRows.Next() {
		var roleID int
		var key string
		if err := permRows.Scan(&roleID, &key); err != nil {
			return nil, fmt.Errorf("scan perm: %w", err)
		}
		rolePerms[roleID] = append(rolePerms[roleID], key)
	}

	staffMap := map[int]struct {
		FirstName, LastName, Position string
		HireDate                      time.Time
	}{}
	if len(staffIDs) > 0 {
		sRows, err := a.db.Query(fmt.Sprintf(`
			SELECT id, first_name, last_name, COALESCE(position,''), hire_date
			FROM staff WHERE id IN (%s)
		`, joinInts(staffIDs)))
		if err != nil {
			return nil, fmt.Errorf("query staff: %w", err)
		}
		defer sRows.Close()
		for sRows.Next() {
			var id int
			var fn, ln, pos string
			var hd time.Time
			if err := sRows.Scan(&id, &fn, &ln, &pos, &hd); err != nil {
				return nil, fmt.Errorf("scan staff: %w", err)
			}
			staffMap[id] = struct {
				FirstName, LastName, Position string
				HireDate                      time.Time
			}{fn, ln, pos, hd}
		}
	}

	custMap := map[int]struct {
		FirstName, LastName, Email, Phone string
	}{}
	if len(customerIDs) > 0 {
		cRows, err := a.db.Query(fmt.Sprintf(`
			SELECT id, first_name, last_name, COALESCE(email,''), COALESCE(phone,'')
			FROM customers WHERE id IN (%s)
		`, joinInts(customerIDs)))
		if err != nil {
			return nil, fmt.Errorf("query customers: %w", err)
		}
		defer cRows.Close()
		for cRows.Next() {
			var id int
			var fn, ln, email, phone string
			if err := cRows.Scan(&id, &fn, &ln, &email, &phone); err != nil {
				return nil, fmt.Errorf("scan customer: %w", err)
			}
			custMap[id] = struct {
				FirstName, LastName, Email, Phone string
			}{fn, ln, email, phone}
		}
	}

	type driverMetric struct {
		Active, Completed, Failed int
	}
	driverMets := map[int]driverMetric{}
	if len(staffIDs) > 0 {
		dRows, err := a.db.Query(fmt.Sprintf(`
			SELECT r.driver_id,
			       COUNT(CASE WHEN o.status IN ('Pending','In Transit') THEN 1 END),
			       COUNT(CASE WHEN d.status = 'Delivered' THEN 1 END),
			       COUNT(CASE WHEN d.status = 'Failed' THEN 1 END)
			FROM routes r
			LEFT JOIN deliveries d ON d.route_id = r.id
			LEFT JOIN orders o ON o.id = d.order_id
			WHERE r.driver_id IN (%s)
			GROUP BY r.driver_id
		`, joinInts(staffIDs)))
		if err != nil {
			return nil, fmt.Errorf("query driver metrics: %w", err)
		}
		defer dRows.Close()
		for dRows.Next() {
			var id int
			var m driverMetric
			if err := dRows.Scan(&id, &m.Active, &m.Completed, &m.Failed); err != nil {
				return nil, fmt.Errorf("scan driver metric: %w", err)
			}
			driverMets[id] = m
		}
	}

	type custMetric struct {
		Total, Pending, Delivered int
		Weight                    float64
	}
	custMets := map[int]custMetric{}
	if len(customerIDs) > 0 {
		cRows, err := a.db.Query(fmt.Sprintf(`
			SELECT customer_id,
			       COUNT(*),
			       COUNT(CASE WHEN status = 'Pending' THEN 1 END),
			       COUNT(CASE WHEN status = 'Delivered' THEN 1 END),
			       COALESCE(SUM(total_weight), 0)
			FROM orders
			WHERE customer_id IN (%s)
			GROUP BY customer_id
		`, joinInts(customerIDs)))
		if err != nil {
			return nil, fmt.Errorf("query customer metrics: %w", err)
		}
		defer cRows.Close()
		for cRows.Next() {
			var id int
			var m custMetric
			if err := cRows.Scan(&id, &m.Total, &m.Pending, &m.Delivered, &m.Weight); err != nil {
				return nil, fmt.Errorf("scan customer metric: %w", err)
			}
			custMets[id] = m
		}
	}

	auditCounts := map[int]int{}
	lastActions := map[int]time.Time{}
	if len(userRows) > 0 {
		userIDs := make([]int, len(userRows))
		for i, u := range userRows {
			userIDs[i] = u.ID
		}
		aRows, err := a.db.Query(fmt.Sprintf(`
			SELECT user_id, COUNT(*), MAX(action_timestamp)
			FROM system_audit_logs
			WHERE user_id IN (%s)
			GROUP BY user_id
		`, joinInts(userIDs)))
		if err != nil {
			return nil, fmt.Errorf("query audit summary: %w", err)
		}
		defer aRows.Close()
		for aRows.Next() {
			var uid, cnt int
			var last sql.NullTime
			if err := aRows.Scan(&uid, &cnt, &last); err != nil {
				return nil, fmt.Errorf("scan audit: %w", err)
			}
			auditCounts[uid] = cnt
			if last.Valid {
				lastActions[uid] = last.Time
			}
		}
	}

	type auditRow struct {
		UserID    int
		ID        int
		Action    string
		Timestamp time.Time
	}
	recentMap := map[int][]AuditEntry{}
	if len(userRows) > 0 {
		userIDs := make([]int, len(userRows))
		for i, u := range userRows {
			userIDs[i] = u.ID
		}
		rRows, err := a.db.Query(fmt.Sprintf(`
			SELECT user_id, id, action_performed, action_timestamp
			FROM (
				SELECT user_id, id, action_performed, action_timestamp,
				       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY action_timestamp DESC) AS rn
				FROM system_audit_logs
				WHERE user_id IN (%s)
			) ranked
			WHERE rn <= 10
			ORDER BY user_id, action_timestamp DESC
		`, joinInts(userIDs)))
		if err != nil {
			return nil, fmt.Errorf("query recent audit: %w", err)
		}
		defer rRows.Close()
		for rRows.Next() {
			var ar auditRow
			if err := rRows.Scan(&ar.UserID, &ar.ID, &ar.Action, &ar.Timestamp); err != nil {
				return nil, fmt.Errorf("scan audit entry: %w", err)
			}
			recentMap[ar.UserID] = append(recentMap[ar.UserID], AuditEntry{
				ID:        ar.ID,
				Action:    ar.Action,
				Timestamp: ar.Timestamp.Format(time.RFC3339),
			})
		}
	}

	out := make([]UserDetail, 0, len(userRows))
	for _, ur := range userRows {
		d := UserDetail{
			ID:          ur.ID,
			Username:    ur.Username,
			RoleName:    ur.RoleName,
			Permissions: rolePerms[ur.RoleID],
		}

		if ur.StaffID.Valid {
			sid := int(ur.StaffID.Int64)
			if s, ok := staffMap[sid]; ok {
				hd := s.HireDate.Format("2006-01-02")
				d.Profile = &UserProfile{
					Type:      "staff",
					FirstName: s.FirstName,
					LastName:  s.LastName,
					Position:  strPtr(s.Position),
					HireDate:  strPtr(hd),
				}
			}
			if m, ok := driverMets[sid]; ok {
				ma, mc, mf := m.Active, m.Completed, m.Failed
				d.Metrics = &UserMetrics{
					ActiveOrders:     &ma,
					CompletedOrders:  &mc,
					FailedDeliveries: &mf,
				}
			}
		}

		if ur.CustomerID.Valid {
			cid := int(ur.CustomerID.Int64)
			if c, ok := custMap[cid]; ok {
				d.Profile = &UserProfile{
					Type:      "customer",
					FirstName: c.FirstName,
					LastName:  c.LastName,
					Email:     strPtr(c.Email),
					Phone:     strPtr(c.Phone),
				}
			}
			if m, ok := custMets[cid]; ok {
				mt, mp, md := m.Total, m.Pending, m.Delivered
				mw := m.Weight
				d.Metrics = &UserMetrics{
					TotalOrders:     &mt,
					PendingOrders:   &mp,
					DeliveredOrders: &md,
					TotalWeight:     &mw,
				}
			}
		}

		if d.Metrics == nil {
			d.Metrics = &UserMetrics{}
		}
		d.Metrics.AuditLogCount = auditCounts[ur.ID]
		if la, ok := lastActions[ur.ID]; ok {
			s := la.Format(time.RFC3339)
			d.Metrics.LastActionAt = &s
		}

		d.RecentActions = recentMap[ur.ID]
		if d.RecentActions == nil {
			d.RecentActions = []AuditEntry{}
		}

		out = append(out, d)
	}

	return out, nil
}

// User CRUD payloads

type StaffPayload struct {
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Position  string `json:"position"`
	HireDate  string `json:"hire_date"` // "2006-01-02"
}

type CustomerPayload struct {
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Email     string `json:"email"`
	Phone     string `json:"phone"`
}

type UserCreat struct {
	Username         string           `json:"username"`
	Password         string           `json:"password"`
	RoleID           int              `json:"role_id"`
	StaffProfile     *StaffPayload    `json:"staff_profile,omitempty"`
	CustomerProfile  *CustomerPayload `json:"customer_profile,omitempty"`
}

type UserUpdate struct {
	ID               int              `json:"id"`
	Username         string           `json:"username"`
	Password         string           `json:"password"`
	RoleID           int              `json:"role_id"`
	StaffProfile     *StaffPayload    `json:"staff_profile,omitempty"`
	CustomerProfile  *CustomerPayload `json:"customer_profile,omitempty"`
}

func (a *App) CreateUser(payload UserCreat) (*UserDetail, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	if !a.hasPermission("manage_users") {
		return nil, errors.New("permission denied")
	}
	if payload.Username == "" || payload.Password == "" {
		return nil, errors.New("username and password are required")
	}

	var roleName string
	err := a.db.QueryRow("SELECT role_name FROM roles WHERE id = ?", payload.RoleID).Scan(&roleName)
	if err != nil {
		return nil, fmt.Errorf("query role: %w", err)
	}

	var staffID, customerID sql.NullInt64

	if payload.StaffProfile != nil {
		var hireDate interface{}
		if payload.StaffProfile.HireDate != "" {
			hireDate = payload.StaffProfile.HireDate
		}
		res, err := a.db.Exec(
			"INSERT INTO staff(first_name, last_name, position, hire_date) VALUES (?, ?, ?, ?)",
			payload.StaffProfile.FirstName, payload.StaffProfile.LastName,
			payload.StaffProfile.Position, hireDate,
		)
		if err != nil {
			return nil, fmt.Errorf("create staff: %w", err)
		}
		id, err := res.LastInsertId()
		if err != nil {
			return nil, fmt.Errorf("get staff id: %w", err)
		}
		staffID = sql.NullInt64{Int64: id, Valid: true}
	}

	if payload.CustomerProfile != nil {
		res, err := a.db.Exec(
			"INSERT INTO customers(first_name, last_name, email, phone) VALUES (?, ?, ?, ?)",
			payload.CustomerProfile.FirstName, payload.CustomerProfile.LastName,
			payload.CustomerProfile.Email, payload.CustomerProfile.Phone,
		)
		if err != nil {
			return nil, fmt.Errorf("create customer: %w", err)
		}
		id, err := res.LastInsertId()
		if err != nil {
			return nil, fmt.Errorf("get customer id: %w", err)
		}
		customerID = sql.NullInt64{Int64: id, Valid: true}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(payload.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}

	result, err := a.db.Exec(
		"INSERT INTO users(username, password_hash, role_id, staff_id, customer_id) VALUES (?, ?, ?, ?, ?)",
		payload.Username, string(hash), payload.RoleID, staffID, customerID,
	)
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}
	uid, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("get user id: %w", err)
	}
	return &UserDetail{
		ID:       int(uid),
		Username: payload.Username,
		RoleName: roleName,
	}, nil
}

func (a *App) UpdateUser(payload UserUpdate) error {
	if err := a.requireDB(); err != nil {
		return err
	}
	if !a.hasPermission("manage_users") {
		return errors.New("permission denied")
	}
	if payload.Username == "" {
		return errors.New("username is required")
	}

	// Verify user exists first
	var exists bool
	err := a.db.QueryRow("SELECT EXISTS(SELECT 1 FROM users WHERE id = ?)", payload.ID).Scan(&exists)
	if err != nil {
		return fmt.Errorf("check user: %w", err)
	}
	if !exists {
		return errors.New("user not found")
	}

	tx, err := a.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Update linked staff profile if provided
	if payload.StaffProfile != nil {
		var existingStaffID int
		err := tx.QueryRow("SELECT COALESCE(staff_id, 0) FROM users WHERE id = ?", payload.ID).Scan(&existingStaffID)
		if err != nil {
			return fmt.Errorf("check existing staff: %w", err)
		}
		if existingStaffID > 0 {
			var hireDate interface{}
			if payload.StaffProfile.HireDate != "" {
				hireDate = payload.StaffProfile.HireDate
			}
			_, err = tx.Exec(
				"UPDATE staff SET first_name = ?, last_name = ?, position = ?, hire_date = ? WHERE id = ?",
				payload.StaffProfile.FirstName, payload.StaffProfile.LastName,
				payload.StaffProfile.Position, hireDate, existingStaffID,
			)
			if err != nil {
				return fmt.Errorf("update staff: %w", err)
			}
		} else {
			var hireDate interface{}
			if payload.StaffProfile.HireDate != "" {
				hireDate = payload.StaffProfile.HireDate
			}
			res, err := tx.Exec(
				"INSERT INTO staff(first_name, last_name, position, hire_date) VALUES (?, ?, ?, ?)",
				payload.StaffProfile.FirstName, payload.StaffProfile.LastName,
				payload.StaffProfile.Position, hireDate,
			)
			if err != nil {
				return fmt.Errorf("create staff: %w", err)
			}
			sid, err := res.LastInsertId()
			if err != nil {
				return fmt.Errorf("get staff id: %w", err)
			}
			_, err = tx.Exec("UPDATE users SET staff_id = ? WHERE id = ?", sid, payload.ID)
			if err != nil {
				return fmt.Errorf("link staff: %w", err)
			}
		}
	}

	// Update linked customer profile if provided
	if payload.CustomerProfile != nil {
		var existingCustID int
		err := tx.QueryRow("SELECT COALESCE(customer_id, 0) FROM users WHERE id = ?", payload.ID).Scan(&existingCustID)
		if err != nil {
			return fmt.Errorf("check existing customer: %w", err)
		}
		if existingCustID > 0 {
			_, err = tx.Exec(
				"UPDATE customers SET first_name = ?, last_name = ?, email = ?, phone = ? WHERE id = ?",
				payload.CustomerProfile.FirstName, payload.CustomerProfile.LastName,
				payload.CustomerProfile.Email, payload.CustomerProfile.Phone, existingCustID,
			)
			if err != nil {
				return fmt.Errorf("update customer: %w", err)
			}
		} else {
			res, err := tx.Exec(
				"INSERT INTO customers(first_name, last_name, email, phone) VALUES (?, ?, ?, ?)",
				payload.CustomerProfile.FirstName, payload.CustomerProfile.LastName,
				payload.CustomerProfile.Email, payload.CustomerProfile.Phone,
			)
			if err != nil {
				return fmt.Errorf("create customer: %w", err)
			}
			cid, err := res.LastInsertId()
			if err != nil {
				return fmt.Errorf("get customer id: %w", err)
			}
			_, err = tx.Exec("UPDATE users SET customer_id = ? WHERE id = ?", cid, payload.ID)
			if err != nil {
				return fmt.Errorf("link customer: %w", err)
			}
		}
	}

	// Update user fields
	if payload.Password != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(payload.Password), bcrypt.DefaultCost)
		if err != nil {
			return fmt.Errorf("hash password: %w", err)
		}
		_, err = tx.Exec("UPDATE users SET username = ?, password_hash = ?, role_id = ? WHERE id = ?",
			payload.Username, string(hash), payload.RoleID, payload.ID)
	} else {
		_, err = tx.Exec("UPDATE users SET username = ?, role_id = ? WHERE id = ?",
			payload.Username, payload.RoleID, payload.ID)
	}
	if err != nil {
		return fmt.Errorf("update user: %w", err)
	}

	return tx.Commit()
}

func (a *App) DeleteUser(id int) error {
	if err := a.requireDB(); err != nil {
		return err
	}
	if !a.hasPermission("manage_users") {
		return errors.New("permission denied")
	}

	var staffID, customerID int
	err := a.db.QueryRow("SELECT COALESCE(staff_id, 0), COALESCE(customer_id, 0) FROM users WHERE id = ?", id).Scan(&staffID, &customerID)
	if err == sql.ErrNoRows {
		return errors.New("user not found")
	}
	if err != nil {
		return fmt.Errorf("find user: %w", err)
	}

	tx, err := a.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Remove audit log entries first (child records)
	_, err = tx.Exec("DELETE FROM system_audit_logs WHERE user_id = ?", id)
	if err != nil {
		return fmt.Errorf("delete audit logs: %w", err)
	}

	res, err := tx.Exec("DELETE FROM users WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete user: %w", err)
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return errors.New("user not found")
	}

	// Clean up orphaned profile records (best-effort — FK rules may prevent it)
	if staffID > 0 {
		_, err = tx.Exec("DELETE FROM staff WHERE id = ?", staffID)
		if err != nil {
			log.Printf("note: could not delete staff %d (referenced elsewhere): %v", staffID, err)
		}
	}
	if customerID > 0 {
		_, err = tx.Exec("DELETE FROM customers WHERE id = ?", customerID)
		if err != nil {
			log.Printf("note: could not delete customer %d (referenced elsewhere): %v", customerID, err)
		}
	}

	return tx.Commit()
}

func (a *App) GetRoles() ([]db.Role, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	rows, err := a.db.Query("SELECT id, role_name FROM roles ORDER BY id")
	if err != nil {
		return nil, fmt.Errorf("query roles: %w", err)
	}
	defer rows.Close()

	var roles []db.Role
	for rows.Next() {
		var r db.Role
		if err := rows.Scan(&r.ID, &r.RoleName); err != nil {
			return nil, fmt.Errorf("scan role: %w", err)
		}
		roles = append(roles, r)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}

	return roles, nil
}
