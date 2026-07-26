SELECT
  blob3 AS referrer,
  sum(_sample_interval) AS download_clicks
FROM audio_lounge_downloads
WHERE
  index1 = 'download'
  AND timestamp >= NOW() - INTERVAL '30' DAY
GROUP BY referrer
ORDER BY download_clicks DESC
LIMIT 50;
