import http from 'k6/http';
import { check, sleep } from 'k6';

// Test config for 100 Concurrent Users to match initial requirement
export const options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp up to 50 users
    { duration: '1m', target: 100 },  // Stay at 100 CCU (Concurrent Users)
    { duration: '30s', target: 0 },   // Ramp down to 0
  ],
};

export default function () {
  const res = http.get('http://localhost:8080/health');
  check(res, {
    'is status 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });
  sleep(1); // Wait 1 second between requests
}
