package main

import (
	"context"
	"database/sql"
	"db_practice_app/db"
	"log"
	"strconv"
	"strings"
)

// App struct
type App struct {
	ctx         context.Context
	db          *sql.DB
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
		log.Fatal(err)
	}
	a.db = database
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




