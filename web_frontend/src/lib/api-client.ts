import axios from 'axios';

export const api = axios.create({
  baseURL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080/api',
  headers: {
    'Content-Type': 'application/json',
  },
  withCredentials: true, // For HttpOnly Cookies
});

// Interceptor for Error Handling
api.interceptors.response.use(
  (response) => response,
  (error) => {
    // Implement global error logging or notification here
    console.error('API Error:', error.response?.data || error.message);
    return Promise.reject(error);
  }
);
