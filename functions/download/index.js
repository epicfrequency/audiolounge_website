const APP_STORE_URL =
  "https://apps.apple.com/us/app/audio-lounge/id6767935421?mt=12";

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);

  // Analytics Engine writes are non-blocking. A failure here should never
  // prevent the visitor from reaching the Mac App Store.
  try {
    env.DOWNLOAD_ANALYTICS.writeDataPoint({
      blobs: [
        "download_click",
        url.pathname,
        request.headers.get("Referer") || "direct",
        request.cf?.country || "unknown",
        request.cf?.deviceType || "unknown"
      ],
      doubles: [1],
      indexes: ["download"]
    });
  } catch (error) {
    console.error("Download analytics write failed:", error);
  }

  return Response.redirect(APP_STORE_URL, 302);
}
