// 临时预览服务器：托管 build/web，SPA 兜底到 index.html。绑定 0.0.0.0 供局域网手机访问。用完即删。
const http = require('http');
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, 'build', 'web');
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.mp4': 'video/mp4', '.ico': 'image/x-icon',
};
http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  let file = path.join(root, p);
  if (!file.startsWith(root)) { res.writeHead(403); return res.end(); }
  fs.stat(file, (err, st) => {
    if (!err && st.isFile()) return send(file);
    file = path.join(root, 'index.html');
    return send(file);
  });
  function send(f) {
    fs.readFile(f, (e, data) => {
      if (e) { res.writeHead(404); return res.end(); }
      res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' });
      res.end(data);
    });
  }
}).listen(8090, '0.0.0.0', () => console.log('serving build/web on http://0.0.0.0:8090'));
