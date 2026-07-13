package command

import (
	"context"
	"testing"

	"github.com/golden_p/backend/internal/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// Mock objects
type MockUserRepository struct {
	mock.Mock
}

func (m *MockUserRepository) GetByID(ctx context.Context, id string) (*domain.User, error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*domain.User), args.Error(1)
}

func (m *MockUserRepository) GetUsersByIDs(ctx context.Context, ids []string) ([]*domain.User, error) {
	args := m.Called(ctx, ids)
	return args.Get(0).([]*domain.User), args.Error(1)
}

type MockEventPublisher struct {
	mock.Mock
}

func (m *MockEventPublisher) PublishUserCreatedEvent(ctx context.Context, userID, email string) error {
	args := m.Called(ctx, userID, email)
	return args.Error(0)
}

func TestCreateUserHandler_Handle(t *testing.T) {
	mockRepo := new(MockUserRepository)
	mockPub := new(MockEventPublisher)

	// Expect publisher to be called
	mockPub.On("PublishUserCreatedEvent", mock.Anything, mock.AnythingOfType("string"), "test@domain.com").Return(nil)

	handler := NewCreateUserHandler(mockRepo, mockPub)
	
	cmd := CreateUserCommand{
		Email: "test@domain.com",
		Role:  "admin",
	}

	user, err := handler.Handle(context.Background(), cmd)

	assert.NoError(t, err)
	assert.NotNil(t, user)
	assert.Equal(t, "test@domain.com", user.Email)
	assert.Equal(t, "admin", user.Role)

	mockPub.AssertExpectations(t)
}
