package query

import (
	"context"

	"github.com/golden_p/backend/internal/domain"
	"github.com/golden_p/backend/internal/repository"
)

type GetUserQuery struct {
	ID string
}

type GetUserHandler interface {
	Handle(ctx context.Context, q GetUserQuery) (*domain.User, error)
}

type getUserHandler struct {
	repo repository.UserRepository
}

func NewGetUserHandler(repo repository.UserRepository) GetUserHandler {
	return &getUserHandler{repo: repo}
}

func (h *getUserHandler) Handle(ctx context.Context, q GetUserQuery) (*domain.User, error) {
	// Separate Read Model (Query) using the repository
	return h.repo.GetByID(ctx, q.ID)
}
