// Ember relay server (Cloudflare Worker + one Durable Object per car).
//
// The car (over LTE) and the phone (over the internet) can't reach each other
// directly, so both talk to this small mailbox:
//
//   car   POST /v1/{carId}/report   signed status + GPS  -> gets queued commands back
//   phone GET  /v1/{carId}/state    latest report (phone checks the car's signature)
//   phone POST /v1/{carId}/command  a command signed end-to-end with the car's key
//   phone POST /v1/{carId}/live     ask the car to report every few seconds for 2 min
//
// The server never knows the car's secret key. It can't forge reports or
// commands; it only stores and forwards them. Requests carry a bearer token
// derived from the key; the first token seen for a car is remembered (as a
// SHA-256 hash) and every later request must match it.

const MAX_QUEUED = 8;
const COMMAND_TTL_MS = 5 * 60 * 1000;
const LIVE_MS = 2 * 60 * 1000;
const MAX_BODY = 2048;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/v1\/([0-9a-f]{16})\/(report|state|command|live)$/);
    if (!m) {
      if (url.pathname === "/") return json({ service: "ember-relay", ok: true });
      return json({ error: "not found" }, 404);
    }
    const carId = m[1];
    const stub = env.CARS.get(env.CARS.idFromName(carId));
    return stub.fetch(request);
  },
};

export class CarMailbox {
  constructor(state, env) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const action = url.pathname.split("/").pop();

    // --- auth: trust-on-first-use bearer token -------------------------------
    const auth = request.headers.get("Authorization") || "";
    const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
    if (!/^[0-9a-f]{32}$/.test(token)) return json({ error: "missing token" }, 401);
    const tokenHash = await sha256Hex(token);
    const known = await this.storage.get("tokenHash");
    if (!known) await this.storage.put("tokenHash", tokenHash);
    else if (!timingSafeEqual(known, tokenHash)) return json({ error: "wrong token" }, 401);

    const now = Date.now();

    if (action === "report" && request.method === "POST") {
      const body = await request.text();
      const sig = request.headers.get("X-Ember-Sig") || "";
      if (body.length > MAX_BODY) return json({ error: "too large" }, 413);
      if (!/^[0-9a-f]{32}$/.test(sig)) return json({ error: "missing signature" }, 400);
      await this.storage.put("state", { report: body, sig, receivedAt: now });

      // Hand over (and remove) any commands still fresh.
      const queue = ((await this.storage.get("queue")) || []).filter((c) => now - c.at < COMMAND_TTL_MS);
      await this.storage.put("queue", []);
      const liveUntil = (await this.storage.get("liveUntil")) || 0;
      return json({ commands: queue.map((c) => c.packet), fast: liveUntil > now });
    }

    if (action === "state" && request.method === "GET") {
      const state = await this.storage.get("state");
      if (!state) return json({ error: "no report yet" }, 404);
      return json(state);
    }

    if (action === "command" && request.method === "POST") {
      let payload;
      try { payload = await request.json(); } catch { return json({ error: "bad json" }, 400); }
      const packet = String(payload.packet || "");
      // [cmd 1][time 4][nonce 8][mac 16] = 29 bytes = 58 hex characters
      if (!/^[0-9a-f]{58}$/.test(packet)) return json({ error: "bad packet" }, 400);
      const queue = ((await this.storage.get("queue")) || []).filter((c) => now - c.at < COMMAND_TTL_MS);
      queue.push({ packet, at: now });
      await this.storage.put("queue", queue.slice(-MAX_QUEUED));
      // A command implies the user wants a quick answer.
      await this.storage.put("liveUntil", now + LIVE_MS);
      return json({ queued: true }, 202);
    }

    if (action === "live" && request.method === "POST") {
      await this.storage.put("liveUntil", now + LIVE_MS);
      return json({ liveUntil: now + LIVE_MS });
    }

    return json({ error: "method not allowed" }, 405);
  }
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
