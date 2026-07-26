SELECT
  sum(_sample_interval) AS download_clicks
FROM audio_lounge_downloads
WHERE
  index1 = 'download'
  AND timestamp >= NOW() - INTERVAL '30' DAY;
