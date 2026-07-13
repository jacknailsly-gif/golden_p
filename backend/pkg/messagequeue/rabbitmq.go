package messagequeue

import (
	"log"

	amqp "github.com/rabbitmq/amqp091-go"
	"go.uber.org/fx"
)

func NewRabbitMQConnection() *amqp.Connection {
	conn, err := amqp.Dial("amqp://guest:guest@localhost:5672/")
	if err != nil {
		log.Printf("Failed to connect to RabbitMQ (Mocking connection for now): %v", err)
		return nil
	}
	return conn
}

var RabbitMQModule = fx.Provide(NewRabbitMQConnection)
