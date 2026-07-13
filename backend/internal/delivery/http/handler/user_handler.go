package handler

import (
	"encoding/base64"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

type UserHandler struct {}

func NewUserHandler() *UserHandler {
	return &UserHandler{}
}

func (h *UserHandler) Login(c *gin.Context) {
	// Mock login behavior
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  "user-123",
		"role": "admin",
		"exp":  time.Now().Add(time.Hour).Unix(),
	})

	tokenString, _ := token.SignedString([]byte("super-secret-key-for-golden-p"))

	// Set HttpOnly Secure Cookie (Secure is false for localhost, true for production)
	c.SetCookie("access_token", tokenString, 3600, "/", "localhost", false, true)
	c.JSON(http.StatusOK, gin.H{"message": "Logged in"})
}

func (h *UserHandler) ListUsers(c *gin.Context) {
	// Cursor Pagination Example
	cursorBase64 := c.Query("cursor")
	limit := c.DefaultQuery("limit", "10")

	// Decode cursor
	cursorStr, _ := base64.StdEncoding.DecodeString(cursorBase64)
	
	c.JSON(http.StatusOK, gin.H{
		"data": []string{"user1", "user2"}, // Mock data
		"next_cursor": base64.StdEncoding.EncodeToString([]byte("user2_id")),
		"limit": limit,
		"decoded_cursor": string(cursorStr),
	})
}

func (h *UserHandler) ProcessPayment(c *gin.Context) {
	// Critical endpoint using Idempotency middleware
	c.JSON(http.StatusOK, gin.H{"message": "Payment processed successfully"})
}
