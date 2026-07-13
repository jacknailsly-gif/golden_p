package main

import (
	"context"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/golden_p/backend/internal/delivery/websocket"
	"go.uber.org/fx"
)

func NewHTTPServer(lc fx.Lifecycle) *http.Server {
	// Initialize Gin Router
	router := gin.Default()

	// Add CORS middleware just in case
	router.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Next()
	})

	// Health Check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "OK"})
	})

	// Initialize WSServer
	wsServer := websocket.NewWSServer()

	// Mount WebSocket endpoints
	router.GET("/ws/signals", wsServer.HandleConnections)
	router.GET("/ws/admin", wsServer.HandleAdminDashboard)

	srv := &http.Server{
		Addr:    ":8080",
		Handler: router,
	}

	lc.Append(fx.Hook{
		OnStart: func(ctx context.Context) error {
			fmt.Println("Starting Gin HTTP server at :8080")
			go srv.ListenAndServe()
			return nil
		},
		OnStop: func(ctx context.Context) error {
			fmt.Println("Stopping HTTP server")
			return srv.Shutdown(ctx)
		},
	})
	return srv
}

func main() {
	app := fx.New(
		fx.Provide(
			NewHTTPServer,
		),
		fx.Invoke(func(*http.Server) {}),
	)
	app.Run()
}
