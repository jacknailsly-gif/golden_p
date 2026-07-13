package database

import (
	"database/sql"

	_ "github.com/lib/pq"
	"go.uber.org/fx"
)

func NewPostgresDB() (*sql.DB, error) {
	// In a real app, read from environment variables
	dsn := "host=localhost port=5432 user=postgres password=secret dbname=golden_p sslmode=disable"
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	// Connection pool settings for scalability
	db.SetMaxOpenConns(100)
	db.SetMaxIdleConns(20)
	
	return db, nil
}

var PostgresModule = fx.Provide(NewPostgresDB)
