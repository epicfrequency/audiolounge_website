# audiolounge-site v4

Static website for https://audiolounge.app.

## Local preview

Double-click `index.html`, or run:

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Production routes

- `/`
- `/support/`
- `/privacy/`

The root also contains `support.html` and `privacy.html` so local double-click preview works correctly.

## Images

All product screenshots and the app icon are the original PNG files supplied by the product owner. They are copied byte-for-byte and are not converted or recompressed.

## Cloudflare

Deploy the repository root as static assets. No build command is required.


## v4.1

The Queue and Audio Path screenshots use equal 8:5 display frames. Original PNG files are unchanged; matching is handled only through CSS.


## SEO and AI discovery

Added without redesigning the existing homepage:

- SoftwareApplication and WebSite JSON-LD
- FAQ page and FAQPage JSON-LD
- `llms.txt` and `llms-full.txt`
- richer Open Graph and Twitter metadata
- enhanced sitemap and robots directives
- web app manifest and security contact
- breadcrumb structured data on Support and Privacy

After deployment, submit `https://audiolounge.app/sitemap.xml` to Google Search Console and Bing Webmaster Tools.
