package websocket

import (
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// ClientData represents real data of a connected mobile app
type ClientData struct {
	ID     string `json:"id"`
	Device string `json:"device"`
	Plan   string `json:"plan"`
	Ping   string `json:"ping"`
	Action string `json:"action"`
}

type WSServer struct {
	mu           sync.Mutex
	clients      map[*websocket.Conn]ClientData
	adminClients map[*websocket.Conn]bool
}

func NewWSServer() *WSServer {
	srv := &WSServer{
		clients:      make(map[*websocket.Conn]ClientData),
		adminClients: make(map[*websocket.Conn]bool),
	}
	// Start broadcasting metrics to dashboard
	go srv.broadcastMetrics()
	return srv
}

func (ws *WSServer) HandleConnections(c *gin.Context) {
	// Authenticate mobile users via JWT (usually passed as query param for WS)
	tokenString := c.Query("token")
	if tokenString != "" {
		token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
			return []byte("super-secret-key-for-golden-p"), nil
		})
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid JWT token"})
			return
		}
	}

	// Upgrade connection
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("WebSocket Upgrade Error:", err)
		return
	}

	// Register Client
	device := c.GetHeader("User-Agent")
	if device == "" || len(device) > 30 {
		device = "Golden P Mobile App"
	}
    ip := c.ClientIP()
    if ip == "::1" || ip == "127.0.0.1" {
        ip = "Localhost"
    }

	clientData := ClientData{
		ID:     "USR-" + ip,
		Device: device,
		Plan:   "Pro Trader",
		Ping:   "8ms",
		Action: "Receiving WSS Signals",
	}

	ws.mu.Lock()
	ws.clients[conn] = clientData
	ws.mu.Unlock()

	defer func() {
		ws.mu.Lock()
		delete(ws.clients, conn)
		ws.mu.Unlock()
		conn.Close()
	}()

	// Send prediction signals (Simulating real-time business logic)
	go func() {
		for {
			time.Sleep(3 * time.Second)
			signal := map[string]interface{}{
				"type": "prediction_signal",
				"data": map[string]float64{
					"BTC/USD": 65000.50,
				},
				"timestamp": time.Now().Unix(),
			}
			ws.mu.Lock()
			if _, exists := ws.clients[conn]; !exists {
				ws.mu.Unlock()
				break
			}
			err := conn.WriteJSON(signal)
			ws.mu.Unlock()
			if err != nil {
				break
			}
		}
	}()

	// Keep alive loop
	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			break
		}
	}
}

func (ws *WSServer) HandleAdminDashboard(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("Admin WS Upgrade Error:", err)
		return
	}
	ws.mu.Lock()
	ws.adminClients[conn] = true
	ws.mu.Unlock()

	defer func() {
		ws.mu.Lock()
		delete(ws.adminClients, conn)
		ws.mu.Unlock()
		conn.Close()
	}()

	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			break
		}
	}
}

func (ws *WSServer) broadcastMetrics() {
	for {
		time.Sleep(2 * time.Second)

		ws.mu.Lock()
		ccu := len(ws.clients)
		userList := make([]ClientData, 0, ccu)
		for _, data := range ws.clients {
			userList = append(userList, data)
		}

		metricsPayload := map[string]interface{}{
			"type":        "admin_metrics",
			"ccu":         ccu,
			"total_users": 1542, // Mock total registered users from Database
			"users":       userList,
		}

		for adminConn := range ws.adminClients {
			err := adminConn.WriteJSON(metricsPayload)
			if err != nil {
				adminConn.Close()
				delete(ws.adminClients, adminConn)
			}
		}
		ws.mu.Unlock()
	}
}
