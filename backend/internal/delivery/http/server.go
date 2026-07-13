package http

import (
	"context"

	"github.com/gin-gonic/gin"
	"github.com/golden_p/backend/internal/delivery/http/handler"
	"github.com/golden_p/backend/internal/delivery/http/middleware"
	"github.com/golden_p/backend/internal/delivery/websocket"
	"github.com/redis/go-redis/v9"
	"go.uber.org/fx"
)

func NewGinServer(lc fx.Lifecycle, redisClient *redis.Client) *gin.Engine {
	r := gin.Default()

	// Global Rate Limiting
	r.Use(middleware.RateLimitMiddleware(redisClient))

	userHandler := handler.NewUserHandler()
	wsServer := websocket.NewWSServer()

	// Public routes
	r.POST("/login", userHandler.Login)
	
	// WebSocket routes (Authentication handled inside the handler)
	r.GET("/ws/signals", wsServer.HandleConnections)

	// Protected routes
	auth := r.Group("/")
	auth.Use(middleware.AuthMiddleware())
	{
		// Cursor pagination and RBAC
		auth.GET("/users", middleware.RBACMiddleware("admin"), userHandler.ListUsers)
		
		// Idempotency for critical endpoints
		auth.POST("/payments", middleware.IdempotencyMiddleware(redisClient), userHandler.ProcessPayment)
	}

	lc.Append(fx.Hook{
		OnStart: func(ctx context.Context) error {
			go r.Run(":8080")
			return nil
		},
	})

	return r
}

var HttpServerModule = fx.Provide(NewGinServer)
