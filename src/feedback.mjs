const json = (data, status = 200, headers = {}) => Response.json(data, { status, headers: { 'Cache-Control': 'no-store', ...headers } });

export async function feedback(request, env) {
  const url = new URL(request.url);
  if (!env.FEEDBACK) return json({ error: 'The board is temporarily unavailable. Please email support@audiolounge.app.' }, 503);
  if (!['GET', 'POST', 'DELETE'].includes(request.method)) return json({ error: 'Method not allowed.' }, 405);
  if (request.method !== 'GET' && request.headers.get('Origin') !== url.origin) return json({ error: 'Please submit from this website.' }, 403);
  let visitor = request.headers.get('Cookie')?.match(/(?:^|;\s*)al_visitor=([a-f0-9-]{36})(?:;|$)/)?.[1];
  const fresh = !visitor;
  visitor ||= crypto.randomUUID();
  // Only a daily digest is stored for rate limits, never the IP address itself.
  const ip = request.headers.get('CF-Connecting-IP') || 'local';
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${new Date().toISOString().slice(0, 10)}:${ip}`));
  const rateKey = Array.from(new Uint8Array(digest), x => x.toString(16).padStart(2, '0')).join('');
  const headers = new Headers(request.headers);
  headers.set('X-Visitor', visitor);
  headers.set('X-Rate-Key', rateKey);
  if (request.method === 'DELETE') {
    if (!env.FEEDBACK_ADMIN_TOKEN || request.headers.get('Authorization') !== `Bearer ${env.FEEDBACK_ADMIN_TOKEN}`) return json({ error: 'Unauthorized.' }, 401);
  }
  try {
    const response = await env.FEEDBACK.get(env.FEEDBACK.idFromName('public-board')).fetch(new Request(request, { headers }));
    const result = new Response(response.body, response);
    if (fresh) result.headers.append('Set-Cookie', `al_visitor=${visitor}; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000${url.protocol === 'https:' ? '; Secure' : ''}`);
    return result;
  } catch {
    return json({ error: 'The board is temporarily unavailable. Please try again later.' }, 503);
  }
}

export class FeedbackBoard {
  constructor(ctx) {
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS posts (id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL, title TEXT NOT NULL, message TEXT NOT NULL, created INTEGER NOT NULL)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS votes (post TEXT NOT NULL, visitor TEXT NOT NULL, PRIMARY KEY (post, visitor))`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL)`);
  }
  async fetch(request) {
    const url = new URL(request.url);
    const visitor = request.headers.get('X-Visitor');
    if (request.method === 'GET') {
      const kind = url.searchParams.get('kind');
      if (!['issue', 'feature'].includes(kind)) return json({ error: 'Invalid board.' }, 400);
      const before = Number(url.searchParams.get('before') || Date.now() + 1);
      if (!Number.isSafeInteger(before) || before < 0) return json({ error: 'Invalid page.' }, 400);
      const posts = this.sql.exec(`SELECT p.*, (SELECT COUNT(*) FROM votes WHERE post=p.id) AS votes, EXISTS(SELECT 1 FROM votes WHERE post=p.id AND visitor=?) AS voted FROM posts p WHERE kind=? AND created<? ORDER BY created DESC LIMIT 31`, visitor, kind, before).toArray();
      const more = posts.length > 30;
      posts.length = Math.min(posts.length, 30);
      return json({ posts, next: more ? posts.at(-1).created : null });
    }
    const id = /^\/api\/feedback\/([a-f0-9-]{36})(?:\/vote)?$/.exec(url.pathname)?.[1];
    if (request.method === 'DELETE') {
      if (!id) return json({ error: 'Invalid message.' }, 400);
      this.sql.exec('DELETE FROM votes WHERE post=?', id);
      this.sql.exec('DELETE FROM posts WHERE id=?', id);
      return json({ ok: true });
    }
    if (!request.headers.get('Content-Type')?.startsWith('application/json')) return json({ error: 'Expected JSON.' }, 415);
    // Stream with a hard byte limit, including requests without Content-Length.
    const reader = request.body?.getReader();
    if (!reader) return json({ error: 'Missing message.' }, 400);
    let bytes = 0, chunks = [];
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 16000) { await reader.cancel(); return json({ error: 'Message is too long.' }, 413); }
      chunks.push(value);
    }
    let data;
    try { data = JSON.parse(await new Blob(chunks).text()); } catch { return json({ error: 'Invalid message.' }, 400); }
    if (!data || typeof data !== 'object' || Array.isArray(data)) return json({ error: 'Invalid message.' }, 400);
    const now = Date.now();
    const vote = url.pathname.endsWith('/vote');
    if (!(vote ? id : url.pathname === '/api/feedback')) return json({ error: 'Not found.' }, 404);
    const key = `${request.headers.get('X-Rate-Key')}:${vote ? 'vote' : 'post'}:${Math.floor(now / 3600000)}`;
    this.sql.exec('DELETE FROM limits WHERE expires<?', now);
    const count = this.sql.exec('SELECT count FROM limits WHERE key=?', key).toArray()[0]?.count || 0;
    if (count >= (vote ? 120 : 10)) return json({ error: 'Too many requests. Please try again in an hour.' }, 429);
    this.sql.exec('INSERT INTO limits VALUES (?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1', key, now + 3600000);
    if (vote) {
      if (!this.sql.exec("SELECT id FROM posts WHERE id=? AND kind='feature'", id).toArray().length) return json({ error: 'Suggestion not found.' }, 404);
      this.sql.exec('INSERT OR IGNORE INTO votes VALUES (?,?)', id, visitor);
      return json({ votes: this.sql.exec('SELECT COUNT(*) AS total FROM votes WHERE post=?', id).toArray()[0].total, voted: true });
    }
    const text = (key, max) => typeof data[key] === 'string' && data[key].trim().length <= max ? data[key].trim() : '';
    const title = text('title', 120), message = text('message', 3000), name = text('name', 60) || 'Anonymous';
    if (data.website || !['issue', 'feature'].includes(data.kind) || !title || !message) return json({ error: 'Please enter a title and description within the length limits.' }, 400);
    // Distinct timestamps keep pagination stable when submissions arrive together.
    const created = Math.max(now, (this.sql.exec('SELECT MAX(created) AS last FROM posts').toArray()[0].last || 0) + 1);
    const postId = crypto.randomUUID();
    this.sql.exec('INSERT INTO posts VALUES (?,?,?,?,?,?)', postId, data.kind, name, title, message, created);
    return json({ id: postId }, 201);
  }
}
