// Ideaverse Web — Cloudflare Worker Drive proxy (keyless on the client)
//
// WHAT THIS DOES
//   Your browser asks THIS worker for Drive data. The worker adds your API key
//   server-side and forwards to Google. The browser never sees the key, and
//   because the worker returns permissive CORS headers, there is NO CORS error
//   and NO OAuth.
//
// DEPLOY (free, ~3 min — no CLI needed):
//   1. Go to https://workers.cloudflare.com/  (free account)
//   2. "Create" -> "Create Worker" -> replace the code with this file
//   3. Set your key: either edit API_KEY below, OR
//        Settings -> Variables -> Add variable  DRIVE_API_KEY = your_key
//      (Use a key with NO HTTP-referrer restriction, or the worker's request
//       to Google will be blocked. Enable the "Google Drive API" for it.)
//   4. "Deploy" -> you get https://<name>.<subdomain>.workers.dev
//   5. In the app: Settings -> Proxy URL -> paste that -> Save & Sync
//
// The Drive folder must be shared "Anyone with the link can view" (an API key
// alone can only read publicly-shared files, not private ones).

const API_KEY = ""; // fallback only; prefer the DRIVE_API_KEY secret

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const KEY = env.DRIVE_API_KEY || API_KEY;
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    if (request.method === "OPTIONS")
      return new Response(null, { status: 204, headers: cors });

    if (!KEY) return json({ error: "DRIVE_API_KEY not set on the worker" }, 500, cors);

    try {
      let target;
      if (url.pathname.startsWith("/drive/v3/")) {
        const rest = url.pathname.slice("/drive/v3".length) + url.search;
        target = "https://www.googleapis.com/drive/v3" + rest + (url.search ? "&" : "?") + "key=" + KEY;
      } else if (url.pathname.startsWith("/media/")) {
        const id = decodeURIComponent(url.pathname.slice("/media/".length));
        target = "https://www.googleapis.com/drive/v3/files/" + encodeURIComponent(id) + "?alt=media&key=" + KEY;
      } else {
        return new Response(
          "Ideaverse Web Drive proxy. Use /drive/v3/... or /media/{fileId}",
          { status: 200, headers: cors }
        );
      }

      const upstream = await fetch(target, { method: "GET" });
      // Stream the upstream body back and stamp CORS on it.
      const resp = new Response(upstream.body, upstream);
      for (const [k, v] of Object.entries(cors)) resp.headers.set(k, v);
      return resp;
    } catch (e) {
      return json({ error: String(e) }, 502, cors);
    }
  },
};

function json(obj, status, extra) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...(extra || {}) },
  });
}
