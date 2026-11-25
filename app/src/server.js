const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 8080;
const APP_VERSION = process.env.APP_VERSION || '1.0.0';
const startTime = Date.now();

const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');

  if (req.url === '/health') {
    res.writeHead(200);
    return res.end(JSON.stringify({ status: 'healthy', uptimeSec: Math.floor((Date.now() - startTime) / 1000) }));
  }

  if (req.url === '/ready') {
    res.writeHead(200);
    return res.end(JSON.stringify({ status: 'ready' }));
  }

  if (req.url === '/') {
    res.writeHead(200);
    return res.end(JSON.stringify({
      service: 'aks-demo-service',
      version: APP_VERSION,
      pod: os.hostname(),
      timestamp: new Date().toISOString()
    }));
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(PORT, () => {
  console.log(`aks-demo-service v${APP_VERSION} listening on port ${PORT}`);
});
