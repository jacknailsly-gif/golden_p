package repository

import (
	"context"

	"github.com/golden_p/backend/internal/domain"
)

// UserLoader solves the N+1 query problem by batching multiple GetByID requests.
// In production, libraries like `graph-gophers/dataloader` or `vektah/dataloaden`
// are used to queue IDs for a few milliseconds, then executing `GetUsersByIDs` in batch.
type UserLoader struct {
	repo UserRepository
}

func NewUserLoader(repo UserRepository) *UserLoader {
	return &UserLoader{repo: repo}
}

// LoadUser represents the Dataloader API which queues the request
func (l *UserLoader) LoadUser(ctx context.Context, id string) (*domain.User, error) {
	// Placeholder: A real loader queues the ID and waits for a short batch window 
	// before calling l.repo.GetUsersByIDs with all queued IDs.
	// This prevents N+1 queries when fetching a list of items that reference users.
	return l.repo.GetByID(ctx, id)
}
