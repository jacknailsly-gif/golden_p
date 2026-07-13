package logger

import (
	"go.uber.org/fx"
	"go.uber.org/zap"
)

func NewLogger() *zap.Logger {
	// Structured JSON logging for production
	logger, _ := zap.NewProduction()
	return logger
}

var LoggerModule = fx.Provide(NewLogger)
