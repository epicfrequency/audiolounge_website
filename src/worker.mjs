const HALO_BINARY_PATH = /^\/halo\/releases\/([^/]+)\/halo-daemon-linux-(arm64|x86_64)$/;

export default {
  async fetch(request, env) {
    const response = await env.ASSETS.fetch(request);
    const url = new URL(request.url);
    const match = HALO_BINARY_PATH.exec(url.pathname);

    if (
      request.method === "GET" &&
      !request.headers.has("range") &&
      response.status === 200 &&
      match
    ) {
      const [, version, architecture] = match;
      const country = request.cf?.country ?? "unknown";

      env.HALO_DOWNLOADS.writeDataPoint({
        blobs: [version, architecture, country, String(response.status)],
        doubles: [1],
        indexes: [`${version}:${architecture}`],
      });
    }

    return response;
  },
};
