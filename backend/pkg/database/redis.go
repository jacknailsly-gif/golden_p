package database

import (
	"github.com/redis/go-redis/v9"
	"go.uber.org/fx"
)

func NewRedisClient() *redis.Client {
	// In a real app, read from environment variables
	client := redis.NewClient(&redis.Options{
		Addr:     "localhost:6379",
		Password: "", // no password set
		DB:       0,  // use default DB
		PoolSize: 100, // Connection pool size
	})
	return client
}

var RedisModule = fx.Provide(NewRedisClient)
