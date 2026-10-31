# Community feedback

The Help page has a public problem board and a feature table with +1 voting.
No GitHub account is required. Posts and votes use a SQLite-backed Cloudflare
Durable Object; local browser storage is not used as the shared database.

## Run and deploy

Use the existing Cloudflare account for this Worker:

```sh
npx wrangler dev
# After checking the local preview:
npx wrangler login
npx wrangler deploy
```

The `feedback-v1` migration provisions the storage on deploy; no separate
D1 database ID is needed. Production data is separate from local preview data.
Do not revert the Durable Object migration or remove the binding after launch.
Static-only hosting / `python3 -m http.server` cannot serve the feedback API.

## Moderation

Set a private administrator token with `npx wrangler secret put FEEDBACK_ADMIN_TOKEN`.
Keep it out of HTML, browser JavaScript, URLs, and Git. List post IDs through
`GET /api/feedback?kind=issue` or `?kind=feature` (use `before` for pagination).
Remove spam using an authenticated `DELETE /api/feedback/POST_ID` request with
`Authorization: Bearer TOKEN` and `Origin: https://audiolounge.app` headers.
Deleting a post removes its votes too. There is no public administration UI.
Until a token is configured, deletion requests are denied. Use the support email
for visitor removal requests.

## Limits

Posts are plain text with 120-character titles and 3,000-character descriptions.
Requests have a hard 16 KB body limit. Per daily IP digest, posting is limited to
10 requests per clock hour and voting to 120 requests per clock hour. A hidden
honeypot catches basic form bots. Shared networks share these limits.
An HttpOnly, SameSite visitor cookie prevents accidental repeat votes from the
same browser. Clearing cookies or changing browsers can bypass this; anonymous
voting is not proof of unique identity. Do not claim otherwise.

These checks reduce casual spam; they do not prevent a distributed attack.
For public launch, use Cloudflare's edge rate limiting / managed protection for
`/api/feedback*` as available on the account, and monitor traffic and storage.
No CAPTCHA or login is required in this first version.

## Verification

Run `node tests/feedback.mjs` against a disposable local `wrangler dev` instance.
It creates local test posts and exercises persistence, visitor votes, validation,
rate limits, and unauthorized deletion. It does not contact production by default.
