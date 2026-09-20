import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json',
  '.png': 'image/png', '.jpeg': 'image/jpeg', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml' };

// A private server per test isolates the origin, IndexedDB, caches and deploy
// version. Serve the actual Pages tree, mounted below a project path. No mocks,
// alternate worker, storage stubs or production test hooks.
export async function startServer() {
  let build = 'acceptance-a';
  const server = createServer(async (req, res) => {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    if (!pathname.startsWith('/cadence/')) { res.writeHead(404).end(); return; }
    const relative = decodeURIComponent(pathname.slice('/cadence/'.length));
    const path = resolve(root, relative + (relative.endsWith('/') ? 'index.html' : ''));
    if (!path.startsWith(root.endsWith(sep) ? root : root + sep)) { res.writeHead(404).end(); return; }
    try {
      let body = await readFile(path);
      // Match the deployment's sole transformation of the application worker.
      if (relative === 'app/sw.js') body = Buffer.from(body.toString().replaceAll('__BUILD__', build));
      res.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream',
        'Cache-Control': 'no-store' });
      res.end(body);
    } catch { res.writeHead(404).end(); }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}/cadence/app/`,
    deploy: () => { build = 'acceptance-b'; },
    close: () => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }),
  };
}
