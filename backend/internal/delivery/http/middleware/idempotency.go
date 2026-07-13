package middleware

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func IdempotencyMiddleware(redisClient *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		idempotencyKey := c.GetHeader("X-Idempotency-Key")
		if idempotencyKey == "" {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "X-Idempotency-Key is required"})
			return
		}

		key := "idemp:" + idempotencyKey
		ctx := context.Background()

		// Try to set key if not exists
		set, err := redisClient.SetNX(ctx, key, "processing", 24*time.Hour).Result()
		if err != nil || !set {
			// Already exists, meaning duplicate request
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{"error": "Duplicate request (Idempotent)"})
			return
		}

		c.Next()

		// If successful, we update the status to "completed"
		redisClient.Set(ctx, key, "completed", 24*time.Hour)
	}
}
