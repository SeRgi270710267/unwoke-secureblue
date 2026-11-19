// Streams one private R2 object after Cloudflare Access has allowed the request.
// The bucket has no public r2.dev hostname. Only Silverblue Trivalent is served.

const SERVED = new Set(["unwoke-silverblue-trivalent"]);
const FILE = /^(?:latest\.iso|SHA256SUMS|SHA256SUMS\.sig)$/;

export async function onRequest(context) {
  const { request, env, params } = context;
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("method not allowed", { status: 405 });
  }
  if (!env.ISOS) {
    return new Response("download unavailable", { status: 503 });
  }
  const parts = params.path;
  const key = Array.isArray(parts) ? parts.join("/") : String(parts || "");
  const slash = key.indexOf("/");
  const flavor = slash === -1 ? "" : key.slice(0, slash);
  const file = slash === -1 ? "" : key.slice(slash + 1);
  if (!SERVED.has(flavor) || !FILE.test(file)) {
    return new Response("not found", { status: 404 });
  }
  const range = request.headers.get("Range");
  let object;
  try {
    object = await env.ISOS.get(key, range ? { range: request.headers } : undefined);
  } catch (_err) {
    return new Response("not found", { status: 404 });
  }
  if (!object) {
    return new Response("not found", { status: 404 });
  }
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "private, no-store");
  headers.set("accept-ranges", "bytes");
  if (key.endsWith("/latest.iso")) {
    headers.set("content-disposition", 'attachment; filename="latest.iso"');
  }
  const status = object.range ? 206 : 200;
  if (request.method === "HEAD") {
    return new Response(null, { status, headers });
  }
  return new Response(object.body, { status, headers });
}
