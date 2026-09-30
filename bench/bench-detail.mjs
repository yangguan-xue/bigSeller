
const http = await import('node:http');
const agent = new http.Agent({ keepAlive: true, maxSockets: 1000 });
const CONCURRENCY = Number(process.argv[2] || 100);
const DURATION_MS = Number(process.argv[3] || 20000);
const BODY = JSON.stringify({ id: 4 });

function once() {
  return new Promise((resolve, reject) => {
    const req = http.request('http://127.0.0.1:6086/program/' + (process.argv[4] || 'detail') + '', {
      method: 'POST', agent,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(BODY) }
    }, res => { res.resume(); res.on('end', () => resolve(res.statusCode)); });
    req.on('error', reject);
    req.end(BODY);
  });
}

async function worker(endAt, lat, errs) {
  while (Date.now() < endAt) {
    const t0 = performance.now();
    try { await once(); lat.push(performance.now() - t0); }
    catch (e) { errs.push(String(e).slice(0, 80)); }
  }
}

for (let i = 0; i < 300; i++) await once();
const lat = [], errs = [];
const endAt = Date.now() + DURATION_MS;
const t0 = Date.now();
await Promise.all(Array.from({ length: CONCURRENCY }, () => worker(endAt, lat, errs)));
const elapsed = (Date.now() - t0) / 1000;
lat.sort((a, b) => a - b);
const p = q => lat[Math.min(lat.length - 1, Math.floor(lat.length * q))].toFixed(1);
console.log(JSON.stringify({
  concurrency: CONCURRENCY, duration_s: elapsed.toFixed(1), total: lat.length, errors: errs.length,
  qps: (lat.length / elapsed).toFixed(0), avg_ms: (lat.reduce((s, v) => s + v, 0) / lat.length).toFixed(1),
  p50: p(0.5), p95: p(0.95), p99: p(0.99), errSample: errs[0] || null
}));
process.exit(0);
