package main

import (
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type AuditLogEntry struct {
	ID        int     `json:"id"`
	UserID    *int    `json:"user_id,omitempty"`
	Username  string  `json:"username"`
	Action    string  `json:"action"`
	Timestamp string  `json:"timestamp"`
}

func (a *App) GetAuditLogs() ([]AuditLogEntry, error) {
	if !a.hasPermission("manage_users") {
		return nil, errors.New("permission denied")
	}

	rows, err := a.db.Query(`
		SELECT al.id, al.user_id, COALESCE(u.username, '[system]'), al.action_performed, al.action_timestamp
		FROM system_audit_logs al
		LEFT JOIN users u ON u.id = al.user_id
		ORDER BY al.action_timestamp DESC
		LIMIT 500
	`)
	if err != nil {
		return nil, fmt.Errorf("query audit logs: %w", err)
	}
	defer rows.Close()

	var entries []AuditLogEntry
	for rows.Next() {
		var e AuditLogEntry
		var userID sql.NullInt64
		var ts time.Time
		if err := rows.Scan(&e.ID, &userID, &e.Username, &e.Action, &ts); err != nil {
			return nil, fmt.Errorf("scan audit log: %w", err)
		}
		if userID.Valid {
			v := int(userID.Int64)
			e.UserID = &v
		}
		e.Timestamp = ts.Format(time.RFC3339)
		entries = append(entries, e)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if entries == nil {
		entries = []AuditLogEntry{}
	}
	return entries, nil
}
