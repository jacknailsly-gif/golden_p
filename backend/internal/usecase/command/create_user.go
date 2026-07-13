package command

import (
	"context"
	"time"

	"github.com/golden_p/backend/internal/domain"
	"github.com/golden_p/backend/internal/repository"
)

type CreateUserCommand struct {
	Email string
	Role  string
}

type CreateUserHandler interface {
	Handle(ctx context.Context, cmd CreateUserCommand) (*domain.User, error)
}

type createUserHandler struct {
	repo      repository.UserRepository
	publisher EventPublisher
}

func NewCreateUserHandler(repo repository.UserRepository, pub EventPublisher) CreateUserHandler {
	return &createUserHandler{repo: repo, publisher: pub}
}

func (h *createUserHandler) Handle(ctx context.Context, cmd CreateUserCommand) (*domain.User, error) {
	// DDD: Aggregate Creation
	user := &domain.User{
		ID:        "gen-uuid", // Example placeholder
		Email:     cmd.Email,
		Role:      cmd.Role,
		CreatedAt: time.Now(),
	}

	// 1. Save to DB (mocking Save method for this example)
	// h.repo.Save(ctx, user)

	// 2. Publish Domain Event to Message Queue asynchronously
	h.publisher.PublishUserCreatedEvent(ctx, user.ID, user.Email)

	return user, nil
}

type EventPublisher interface {
	PublishUserCreatedEvent(ctx context.Context, userID, email string) error
}
