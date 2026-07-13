package messagequeue

import (
	"context"
	"encoding/json"
	"log"

	amqp "github.com/rabbitmq/amqp091-go"
)

type RabbitMQPublisher struct {
	conn *amqp.Connection
}

func NewRabbitMQPublisher(conn *amqp.Connection) *RabbitMQPublisher {
	return &RabbitMQPublisher{conn: conn}
}

type UserCreatedEvent struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
}

func (p *RabbitMQPublisher) PublishUserCreatedEvent(ctx context.Context, userID, email string) error {
	if p.conn == nil {
		return nil // skip if offline
	}

	ch, err := p.conn.Channel()
	if err != nil {
		return err
	}
	defer ch.Close()

	q, err := ch.QueueDeclare("user_created", true, false, false, false, nil)
	if err != nil {
		return err
	}

	event := UserCreatedEvent{UserID: userID, Email: email}
	body, _ := json.Marshal(event)

	err = ch.PublishWithContext(ctx, "", q.Name, false, false, amqp.Publishing{
		ContentType: "application/json",
		Body:        body,
	})

	if err != nil {
		log.Printf("Failed to publish a message: %v", err)
		return err
	}
	return nil
}
