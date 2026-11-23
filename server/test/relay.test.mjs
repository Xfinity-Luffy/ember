// Runs the relay against an in-memory stand-in for Cloudflare's Durable Objects.
//   node server/test/relay.test.mjs
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import worker, { CarMailbox } from "../src/index.js";

class MemoryStorage {
  constructor() { this.map = new Map(); }
  async get(k) { return structuredClone(this.map.get(k)); }
  async put(k, v) { this.map.set(k, structuredClone(v)); }
}
class FakeNamespace {
  constructor() { this.objects = new Map(); }
  idFromName(name) { return name; }
  get(id) {
    if (!this.objects.has(id)) this.objects.set(id, new CarMailbox({ storage: new MemoryStorage() }, {}));
    const obj = this.objects.get(id);
    return { fetch: (req) => obj.fetch(req) };
  }
}
const env = { CARS: new FakeNamespace() };

// Same derivations the car and the app use.
const key = Buffer.from("4243cbbfbd772786df4fc2f9533e446bed0f0815b5a873d8a4f677d1adf96fab", "hex");
const hmacHex = (label) => createHmac("sha256", key).update(label).digest("hex");
const carId = hmacHex("EMBR-ID").slice(0, 16);
const token = hmacHex("EMBR-API").slice(0, 32);
const base = `https://relay.example/v1/${carId}`;

const call = (path, { method = "GET", body, headers = {}, tok = token } = {}) =>
  worker.fetch(new Request(base + path, {
    method, body,
    headers: { Authorization: `Bearer ${tok}`, ...headers },
  }), env);

let passed = 0;
const ok = (name) => { passed++; console.log("ok -", name); };

// Root
assert.equal((await worker.fetch(new Request("https://relay.example/"), env)).status, 200); ok("root responds");

// No report yet
assert.equal((await call("/state")).status, 404); ok("state 404 before any report");

// Wrong token after first use is rejected
assert.equal((await call("/state", { tok: "0".repeat(32) })).status, 401); ok("different token rejected after first use");
assert.equal((await call("/state", { tok: "nope" })).status, 401); ok("malformed token rejected");

// Car reports
const report = JSON.stringify({ v: 1, t: 1763900000, lat: 36.5, lon: -82.3, spd: 0, st: "01000000000000000000" });
const sig = createHmac("sha256", key).update("EMBR-RPT").update(report).digest("hex").slice(0, 32);
let r = await call("/report", { method: "POST", body: report, headers: { "X-Ember-Sig": sig } });
assert.equal(r.status, 200);
let j = await r.json();
assert.deepEqual(j.commands, []); assert.equal(j.fast, false); ok("report accepted, no commands, not fast");

// Report without signature
r = await call("/report", { method: "POST", body: report });
assert.equal(r.status, 400); ok("unsigned report rejected");

// Phone reads it back verbatim
j = await (await call("/state")).json();
assert.equal(j.report, report); assert.equal(j.sig, sig); assert.ok(j.receivedAt > 0); ok("state returns report + signature verbatim");

// Phone queues a command
const packet = "03" + "6923a8a0" + "0011223344556677" + "aa".repeat(16);
r = await call("/command", { method: "POST", body: JSON.stringify({ packet }), headers: { "Content-Type": "application/json" } });
assert.equal(r.status, 202); ok("command queued");
r = await call("/command", { method: "POST", body: JSON.stringify({ packet: "zz" }) });
assert.equal(r.status, 400); ok("malformed command rejected");

// Next report delivers it once, and fast mode is on
j = await (await call("/report", { method: "POST", body: report, headers: { "X-Ember-Sig": sig } })).json();
assert.deepEqual(j.commands, [packet]); assert.equal(j.fast, true); ok("command delivered with next report; fast mode on");
j = await (await call("/report", { method: "POST", body: report, headers: { "X-Ember-Sig": sig } })).json();
assert.deepEqual(j.commands, []); ok("command delivered only once");

// Queue is capped
for (let i = 0; i < 12; i++) await call("/command", { method: "POST", body: JSON.stringify({ packet }) });
j = await (await call("/report", { method: "POST", body: report, headers: { "X-Ember-Sig": sig } })).json();
assert.equal(j.commands.length, 8); ok("queue capped at 8");

// Live mode endpoint
assert.equal((await call("/live", { method: "POST" })).status, 200); ok("live mode accepted");

// Another car is isolated
const other = await worker.fetch(new Request("https://relay.example/v1/0123456789abcdef/state", { headers: { Authorization: `Bearer ${token}` } }), env);
assert.equal(other.status, 404); ok("cars are isolated");

// Bad path
assert.equal((await worker.fetch(new Request("https://relay.example/v1/xyz/state"), env)).status, 404); ok("bad path 404");

console.log(`\nSERVER ALL PASS (${passed} checks)`);
