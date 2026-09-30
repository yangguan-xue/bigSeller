
const http = await import('node:http');
const agent = new http.Agent({ keepAlive: true, maxSockets: 1000 });
const CONCURRENCY = Number(process.argv[2] || 100);
const DURATION_MS = Number(process.argv[3] || 20000);
const PATH = process.argv[4] || 'detail/v2';
const BODY = JSON.stringify({ id: 4 });

function once() {
  return new Promise((resolve, reject) => {
    const req = http.request('http://127.0.0.1:6086/program/' + PATH, {
      method: 'POST', agent,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(BODY) }
    }, res => {
      let chunks = '';
      res.on('data', c => chunks += c);
      res.on('end', () => resolve({ status: res.statusCode, body: chunks }));
    });
    req.on('error', reject);
    req.end(BODY);
  });
}

async function worker(endAt, stat) {
  while (Date.now() < endAt) {
    const t0 = performance.now();
    try {
      const r = await once();
      const ms = performance.now() - t0;
      stat.lat.push(ms);
      if (r.status !== 200) stat.httpErr++;
      else if (r.body.includes('"code":"0"') && r.body.includes('"data":{')) stat.ok++;
      else { stat.bizErr++; if (stat.errSample === null) stat.errSample = r.body.slice(0, 150); }
    } catch (e) { stat.netErr++; }
  }
}

for (let i = 0; i < 300; i++) await once();
const stat = { lat: [], ok: 0, bizErr: 0, httpErr: 0, netErr: 0, errSample: null };
const endAt = Date.now() + DURATION_MS;
const t0 = Date.now();
await Promise.all(Array.from({ length: CONCURRENCY }, () => worker(endAt, stat)));
const elapsed = (Date.now() - t0) / 1000;
stat.lat.sort((a, b) => a - b);
const p = q => stat.lat[Math.min(stat.lat.length - 1, Math.floor(stat.lat.length * q))].toFixed(1);
console.log(JSON.stringify({
  path: PATH, concurrency: CONCURRENCY, duration_s: elapsed.toFixed(1),
  total: stat.lat.length, ok_with_data: stat.ok, biz_error: stat.bizErr, http_error: stat.httpErr, net_error: stat.netErr,
  qps: (stat.lat.length / elapsed).toFixed(0),
  avg_ms: (stat.lat.reduce((s, v) => s + v, 0) / stat.lat.length).toFixed(1),
  p50: p(0.5), p95: p(0.95), p99: p(0.99), errSample: stat.errSample
}));
process.exit(0);
