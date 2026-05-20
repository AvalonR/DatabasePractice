package main

import (
	"context"
	"database/sql"
	"db_practice_app/db"
	"log"
	"strconv"
	"strings"
	"errors"
)

// App struct
type App struct {
	ctx         context.Context
	db          *sql.DB
	dbError     string
	currentUser *AuthenticatedUser
}

func (a *App) hasPermission(perm string) bool {
	if a.currentUser == nil {
		return false
	}
	if a.currentUser.RoleName == "Admin" {
		return true
	}
	for _, p := range a.currentUser.Permissions {
		if p == perm {
			return true
		}
	}
	return false
}

func NewApp() *App {
	return &App{}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	database, err := db.InitDB()
	if err != nil {
		a.dbError = err.Error()
		log.Printf("Database connection failed: %v", err)
		return
	}
	a.db = database
}

func (a *App) GetDBStatus() (map[string]interface{}, error) {
	if a.dbError != "" {
		return map[string]interface{}{
			"connected": false,
			"error":     a.dbError,
		}, nil
	}
	if a.db == nil {
		return map[string]interface{}{
			"connected": false,
			"error":     "Database not initialized",
		}, nil
	}
	if err := a.db.Ping(); err != nil {
		return map[string]interface{}{
			"connected": false,
			"error":     err.Error(),
		}, nil
	}
	return map[string]interface{}{
		"connected": true,
		"error":     "",
	}, nil
}

func (a *App) requireDB() error {
	if a.db == nil {
		msg := "database not connected"
		if a.dbError != "" {
			msg = a.dbError
		}
		return errors.New(msg)
	}
	return nil
}

func (a *App) ReconnectDB() (map[string]interface{}, error) {
	a.db = nil
	a.dbError = ""
	database, err := db.InitDB()
	if err != nil {
		a.dbError = err.Error()
		log.Printf("Reconnect failed: %v", err)
		return map[string]interface{}{
			"connected": false,
			"error":     a.dbError,
		}, nil
	}
	a.db = database
	log.Println("Database reconnected successfully")
	return map[string]interface{}{
		"connected": true,
		"error":     "",
	}, nil
}

func joinInts(vs []int) string {
	parts := make([]string, len(vs))
	for i, v := range vs {
		parts[i] = strconv.Itoa(v)
	}
	return strings.Join(parts, ",")
}

func strPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}




