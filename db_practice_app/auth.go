package main

import (
	"db_practice_app/db"
	"errors"
	"fmt"

	"golang.org/x/crypto/bcrypt"
)

type AuthenticatedUser struct {
	ID          int      `json:"id"`
	Username    string   `json:"username"`
	RoleName    string   `json:"role_name"`
	Permissions []string `json:"permissions"`
	StaffID     *int     `json:"staff_id,omitempty"`
	CustomerID  *int     `json:"customer_id,omitempty"`
}

func (a *App) Auth(username string, password string) (*AuthenticatedUser, error) {
	if err := a.requireDB(); err != nil {
		return nil, err
	}
	var user db.User

	err := a.db.QueryRow("SELECT id, username, password_hash, role_id, staff_id, customer_id FROM users WHERE username = ?", username).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.RoleID, &user.StaffID, &user.CustomerID)
	if err != nil {
		fmt.Println(err)
		return nil, errors.New("invalid username or password")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, errors.New("invalid username or password")
	}

	var roleName string
	err = a.db.QueryRow("SELECT role_name FROM roles WHERE id = ?", user.RoleID).Scan(&roleName)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}

	rows, err := a.db.Query("SELECT p.perm_key FROM permissions p JOIN role_permissions rp ON p.id = rp.permission_id WHERE rp.role_id = ?", user.RoleID)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}
	defer rows.Close()

	var permissions []string
	for rows.Next() {
		var permKey string
		err := rows.Scan(&permKey)
		if err != nil {
			fmt.Println(err)
			return nil, err
		}
		permissions = append(permissions, permKey)
	}

	authUser := &AuthenticatedUser{
		ID:          user.ID,
		Username:    user.Username,
		RoleName:    roleName,
		Permissions: permissions,
	}
	if user.StaffID.Valid {
		v := int(user.StaffID.Int64)
		authUser.StaffID = &v
	}
	if user.CustomerID.Valid {
		v := int(user.CustomerID.Int64)
		authUser.CustomerID = &v
	}
	a.currentUser = authUser
	return authUser, nil
}
