package messagequeue

import (
	"log"

	amqp "github.com/rabbitmq/amqp091-go"
)

type RabbitMQConsumer struct {
	conn *amqp.Connection
}

func NewRabbitMQConsumer(conn *amqp.Connection) *RabbitMQConsumer {
	return &RabbitMQConsumer{conn: conn}
}

func (c *RabbitMQConsumer) StartConsuming() {
	if c.conn == nil {
		return
	}

	ch, err := c.conn.Channel()
	if err != nil {
		log.Printf("Failed to open channel: %v", err)
		return
	}

	msgs, err := ch.Consume("user_created", "", true, false, false, false, nil)
	if err != nil {
		log.Printf("Failed to register a consumer: %v", err)
		return
	}

	go func() {
		for d := range msgs {
			log.Printf("Background Job: Sending Welcome Email to User => %s", string(d.Body))
			// Do heavy background tasks here without blocking API
		}
	}()
}
