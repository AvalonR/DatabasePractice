package db

import (
	"database/sql"

	_ "github.com/go-sql-driver/mysql"
)

var DB *sql.DB

func InitDB() (*sql.DB, error) {
	var err error
	DB, err = sql.Open("mysql", "root:@tcp(127.0.0.1:3306)/delivery_system?parseTime=true")
	if err != nil {
		return nil, err
	}
	return DB, DB.Ping()
}
