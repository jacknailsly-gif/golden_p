package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/golden_p/backend/internal/domain"
	"github.com/redis/go-redis/v9"
)

type UserRepository interface {
	GetByID(ctx context.Context, id string) (*domain.User, error)
	GetUsersByIDs(ctx context.Context, ids []string) ([]*domain.User, error)
}

type userRepository struct {
	db    *sql.DB
	redis *redis.Client
}

func NewUserRepository(db *sql.DB, redis *redis.Client) UserRepository {
	return &userRepository{db: db, redis: redis}
}

func (r *userRepository) GetByID(ctx context.Context, id string) (*domain.User, error) {
	// 1. Try to get from Redis Cache first
	cacheKey := "user:" + id
	val, err := r.redis.Get(ctx, cacheKey).Result()
	if err == nil && val != "" {
		var user domain.User
		if err := json.Unmarshal([]byte(val), &user); err == nil {
			return &user, nil // Cache hit
		}
	}

	// 2. Fallback to PostgreSQL
	query := `SELECT id, email, role, created_at FROM users WHERE id = $1`
	row := r.db.QueryRowContext(ctx, query, id)

	var user domain.User
	if err := row.Scan(&user.ID, &user.Email, &user.Role, &user.CreatedAt); err != nil {
		return nil, err
	}

	// 3. Set Cache in Redis (TTL 10 Minutes)
	if b, err := json.Marshal(user); err == nil {
		r.redis.Set(ctx, cacheKey, string(b), 10*time.Minute)
	}

	return &user, nil
}

func (r *userRepository) GetUsersByIDs(ctx context.Context, ids []string) ([]*domain.User, error) {
	// Implementation to fetch multiple users via `WHERE id IN (...)` to avoid N+1
	// Typically implemented with sqlx.In or pq.Array
	return nil, nil
}
