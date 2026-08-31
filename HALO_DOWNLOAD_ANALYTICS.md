# HALO download analytics

HALO binary downloads are counted at the Cloudflare edge without adding
telemetry to the installer or daemon. A data point is written only for a
successful, non-range `GET` of a public release binary.

The `halo_downloads` dataset stores these ordered fields:

| Field | Meaning |
| --- | --- |
| `blob1` | HALO version |
| `blob2` | `arm64` or `x86_64` |
| `blob3` | Cloudflare country code, or `unknown` |
| `blob4` | HTTP response status |
| `double1` | Event count (`1`) |
| `index1` | `<version>:<architecture>` sampling key |

No IP address, user agent, device name, DAC information, or music data is
written.

## Query totals

Create a Cloudflare API token with `Account Analytics: Read`, then query the
Analytics Engine SQL API. Account ID and token should remain outside this
repository.

```bash
curl "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/analytics_engine/sql" \
  --header "Authorization: Bearer <API_TOKEN>" \
  --data "SELECT blob1 AS version, blob2 AS architecture, SUM(_sample_interval) AS downloads FROM halo_downloads GROUP BY version, architecture ORDER BY version, architecture"
```

For a recent time window, add for example:

```sql
WHERE timestamp >= NOW() - INTERVAL '30' DAY
```

The result counts successful binary responses. Reinstalls, upgrades and
retries are separate downloads, so the number is not a unique-user count.
