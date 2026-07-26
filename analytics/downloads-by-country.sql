SELECT
  blob4 AS country,
  sum(_sample_interval) AS download_clicks
FROM audio_lounge_downloads
WHERE
  index1 = 'download'
  AND timestamp >= NOW() - INTERVAL '30' DAY
GROUP BY country
ORDER BY download_clicks DESC;
