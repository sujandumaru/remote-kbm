const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const html = fs.readFileSync("client/index.html", "utf8");
const match = html.match(/const token =[\s\S]*?\nconnect\(\);/);
assert(match, "connection script not found");

function element() {
  const classes = new Set();
  return {
    textContent: "",
    listeners: {},
    classList: {
      add: name => classes.add(name),
      remove: name => classes.delete(name),
      contains: name => classes.has(name),
    },
    addEventListener(type, callback) {
      this.listeners[type] = callback;
    },
  };
}

const sockets = [];
class FakeWebSocket {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;

  constructor(url) {
    this.url = url;
    this.readyState = FakeWebSocket.CONNECTING;
    this.sent = [];
    sockets.push(this);
  }

  open() {
    this.readyState = FakeWebSocket.OPEN;
    this.onopen();
  }

  close() {
    this.readyState = FakeWebSocket.CLOSING;
  }

  finishClose() {
    this.readyState = FakeWebSocket.CLOSED;
    this.onclose();
  }

  send(message) {
    this.sent.push(message);
  }
}

const dot = element();
const stat = element();
const timers = new Map();
let nextTimer = 1;
const context = {
  URLSearchParams,
  WebSocket: FakeWebSocket,
  clearTimeout(id) {
    timers.delete(id);
  },
  document: {
    getElementById(id) {
      return id === "dot" ? dot : stat;
    },
    createElement() {
      return {};
    },
    head: { appendChild() {} },
  },
  encodeURIComponent,
  fetch: async () => ({ ok: true }),
  JSON,
  localStorage: {
    getItem() { return null; },
    setItem() {},
  },
  location: { host: "pc.test:8765", search: "?k=test" },
  setTimeout(callback) {
    const id = nextTimer++;
    timers.set(id, callback);
    return id;
  },
};

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

async function run() {
  vm.runInNewContext(match[0], context);
  assert.strictEqual(sockets.length, 1);

  stat.listeners.click();
  assert.strictEqual(sockets.length, 2);
  const [stale, active] = sockets;

  stale.open();
  assert.notStrictEqual(stat.textContent, "connected");

  active.open();
  assert.strictEqual(stat.textContent, "connected");
  assert(dot.classList.contains("on"));

  context.send({ t: "move", dx: 1, dy: 1 });
  assert.strictEqual(active.sent.length, 1);
  assert.strictEqual(stale.sent.length, 0);

  stale.finishClose();
  await flush();
  assert.strictEqual(stat.textContent, "connected");

  active.finishClose();
  await flush();
  assert(!dot.classList.contains("on"));
  assert(stat.textContent.includes("tap to retry"));
  assert.strictEqual(timers.size, 1);
}

run().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
