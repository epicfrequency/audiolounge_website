SELECT
  toDate(timestamp) AS day,
  sum(_sample_interval) AS download_clicks
FROM audio_lounge_downloads
WHERE
  index1 = 'download'
  AND timestamp >= NOW() - INTERVAL '30' DAY
GROUP BY day
ORDER BY day DESC;
