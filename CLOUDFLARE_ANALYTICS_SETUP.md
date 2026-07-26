# Cloudflare Analytics Engine setup

This package records each `/download/` request in the Analytics Engine dataset:

`audio_lounge_downloads`

The visitor is then immediately redirected with an HTTP 302 to the Mac App Store.
There is no intermediate HTML page.

## Deploy

1. Remove the separate Cloudflare Redirect Rule for `/download/`.
2. Push this complete folder to the GitHub repository connected to Cloudflare Pages.
3. Wait for the production deployment to finish.
4. Open `https://audiolounge.app/download/` once as a test.

The binding is declared in `wrangler.jsonc`:

- Binding: `DOWNLOAD_ANALYTICS`
- Dataset: `audio_lounge_downloads`

The dataset is created after the first successful data write.

## If the Git deployment does not apply the binding

In Cloudflare:

1. Workers & Pages
2. Open the Audio Lounge Pages project
3. Settings
4. Functions
5. Analytics Engine bindings
6. Add binding:
   - Variable name: `DOWNLOAD_ANALYTICS`
   - Dataset: `audio_lounge_downloads`
7. Redeploy

## Query the count

Create a Cloudflare API token with permission to read Workers Analytics Engine,
then send SQL to:

`https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/analytics_engine/sql`

Example:

```bash
curl "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/analytics_engine/sql"   --header "Authorization: Bearer <API_TOKEN>"   --data "SELECT sum(_sample_interval) AS download_clicks
          FROM audio_lounge_downloads
          WHERE index1 = 'download'
          AND timestamp >= NOW() - INTERVAL '30' DAY"
```

Ready-made SQL files are in the `analytics/` folder.

## Recorded fields

- `blob1`: event name (`download_click`)
- `blob2`: request path
- `blob3`: referrer, or `direct`
- `blob4`: country code
- `blob5`: device type when available
- `double1`: value `1`
- `index1`: `download`

No IP address, email address, account identifier, or music information is stored.
