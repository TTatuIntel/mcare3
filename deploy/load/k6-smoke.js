import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    readiness: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 10),
      timeUnit: '1s',
      duration: __ENV.DURATION || '2m',
      preAllocatedVUs: Number(__ENV.VUS || 20),
      maxVUs: Number(__ENV.MAX_VUS || 100),
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    checks: ['rate>0.99'],
  },
};

const baseUrl = (__ENV.BASE_URL || 'http://127.0.0.1:8000').replace(/\/$/, '');
const authToken = __ENV.AUTH_TOKEN || '';
const sessionPath = __ENV.SESSION_PATH || '';

export default function () {
  const responses = http.batch([
    ['GET', `${baseUrl}/up`, null, { tags: { name: 'liveness' } }],
    ['GET', `${baseUrl}/ready`, null, { tags: { name: 'readiness' } }],
  ]);
  check(responses[0], { 'liveness is 200': (response) => response.status === 200 });
  check(responses[1], { 'readiness is 200': (response) => response.status === 200 });

  if (authToken && sessionPath) {
    const session = http.get(`${baseUrl}${sessionPath}`, {
      headers: { Authorization: `Bearer ${authToken}`, Accept: 'application/json' },
      tags: { name: 'authenticated-session' },
    });
    check(session, { 'session is 200': (response) => response.status === 200 });
  }

  sleep(0.1);
}
