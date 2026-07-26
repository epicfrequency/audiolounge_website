# Audio Lounge website

Static website for https://audiolounge.app.

## Local preview

Double-click `index.html`, or run:

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Production routes

- `/`
- `/blog/`
- `/blog/why-i-built-audio-lounge/`
- `/support/`
- `/privacy/`

Root-level HTML copies are included for convenient local preview.

## Blog

The first post is **Why I Built Audio Lounge**. To add another post:

1. Create a root HTML page for local preview.
2. Create a matching clean-route folder under `/blog/`.
3. Add the post to `blog.html`, `/blog/index.html`, `feed.xml`, and `sitemap.xml`.
4. Add `BlogPosting` JSON-LD and a canonical URL.

## Images

All product screenshots and the app icon are the original PNG assets. They are copied byte-for-byte and are not converted or recompressed.

## Cloudflare

Deploy the repository root as static assets. No build command is required.

```bash
npx wrangler deploy
```
