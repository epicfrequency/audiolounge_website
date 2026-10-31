import assert from 'node:assert/strict';
const base = process.env.FEEDBACK_TEST_URL || 'http://localhost:8787';
let cookie = '';
async function call(path, body, extra = {}) {
  const response = await fetch(base + path, { method: body === undefined ? 'GET' : 'POST', headers: { Origin: base, Cookie: cookie, 'Content-Type': 'application/json', ...extra }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  if (response.headers.has('set-cookie')) cookie = response.headers.get('set-cookie').split(';')[0];
  return { status: response.status, data: await response.json() };
}
assert.equal((await fetch(base + '/help/')).status, 200);
assert.equal((await call('/api/feedback?kind=feature')).status, 200);
assert.ok(cookie.startsWith('al_visitor='));
assert.equal((await call('/api/feedback?kind=nope')).status, 400);
const post = { kind: 'feature', name: 'Local test', title: 'A shared feature', message: '<script>alert(1)</script>' };
assert.equal((await call('/api/feedback', post, { Origin: 'https://other.example' })).status, 403);
assert.equal((await call('/api/feedback', { ...post, message: 'x'.repeat(3001) })).status, 400);
const created = await call('/api/feedback', post);
assert.equal(created.status, 201);
const id = created.data.id;
assert.equal((await call(`/api/feedback/${id}/vote`, {})).data.votes, 1);
assert.equal((await call(`/api/feedback/${id}/vote`, {})).data.votes, 1);
let list = await call('/api/feedback?kind=feature');
assert.equal(list.data.posts.find(p => p.id === id).voted, 1);
cookie = '';
list = await call('/api/feedback?kind=feature');
assert.equal(list.data.posts.find(p => p.id === id).message, post.message);
assert.equal(list.data.posts.find(p => p.id === id).voted, 0);
assert.equal((await call(`/api/feedback/${id}/vote`, {})).data.votes, 2);
const issue = await call('/api/feedback', { ...post, kind: 'issue', title: 'Local test issue' });
assert.equal(issue.status, 201);
assert.equal((await call(`/api/feedback/${issue.data.id}/vote`, {})).status, 404);
assert.ok(!(await call('/api/feedback?kind=feature')).data.posts.some(p => p.id === issue.data.id));
assert.ok((await call('/api/feedback?kind=issue')).data.posts.some(p => p.id === issue.data.id));
assert.equal((await call('/api/feedback', { ...post, message: 'x'.repeat(17000) })).status, 413);
const denied = await fetch(base + `/api/feedback/${id}`, { method: 'DELETE', headers: { Origin: base } });
assert.equal(denied.status, 401);
let limited = false;
for (let i = 0; i < 12; i++) { if ((await call('/api/feedback', post)).status === 429) { limited = true; break; } }
assert.ok(limited, 'Post rate limit must be enforced');
console.log('PASS: shared storage, separate boards, duplicate votes, independent visitors, validation, origin checks, size limits, private moderation, and rate limits.');
