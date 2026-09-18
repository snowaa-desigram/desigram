// k6: «200 человек онлайн». Запуск: make load TARGET=https://api.desigram.localhost:8443
// Пороги ниже — критерий прохождения: job падает, если p95 или доля ошибок вышли за них.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.TARGET || 'http://localhost:8080';

export const options = {
  insecureSkipTLSVerify: true,           // локальный mkcert
  scenarios: {
    online_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 200 },  // разгон
        { duration: '3m', target: 200 },  // плато: 200 онлайн
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.01'],           // < 1% ошибок
    http_req_duration: ['p(95)<300', 'p(99)<800'],
    'http_req_duration{name:ping}': ['p(95)<400'],
  },
};

// Поведение одного пользователя: раз в ~5–10 с что-то делает.
// TODO: заменить на реальные сценарии (логин → проекты → сохранение → экспорт), когда появятся эндпоинты.
export default function () {
  const health = http.get(`${BASE}/health`, { tags: { name: 'health' } });
  check(health, { 'health 200': (r) => r.status === 200 });

  const ping = http.get(`${BASE}/api/ping?message=k6`, { tags: { name: 'ping' } });
  check(ping, { 'ping 200': (r) => r.status === 200, 'ping body': (r) => r.body.includes('pong') });

  sleep(5 + Math.random() * 5);
}
