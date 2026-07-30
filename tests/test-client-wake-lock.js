const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const html = fs.readFileSync("client/index.html", "utf8");
const start = html.indexOf("// Wake Lock API");
const end = html.indexOf("const GAIN_MIN", start);
assert(start >= 0 && end > start, "wake-lock script not found");
const script = html.slice(start, end);

function environment(navigator) {
  const documentListeners = {};
  const windowListeners = {};
  const timers = [];
  const videos = [];
  let mutedAssigned = false;

  const document = {
    hidden: false,
    listeners: documentListeners,
    body: { appendChild() {} },
    addEventListener(type, callback) {
      documentListeners[type] = callback;
    },
    createElement(tag) {
      if (tag === "source") return {};
      const listeners = {};
      const video = {
        currentTime: 0,
        duration: 0,
        listeners,
        paused: true,
        style: {},
        addEventListener(type, callback) {
          listeners[type] = callback;
        },
        appendChild() {},
        play() {
          this.paused = false;
          return Promise.resolve();
        },
        setAttribute() {},
      };
      Object.defineProperty(video, "muted", {
        set() { mutedAssigned = true; },
      });
      videos.push(video);
      return video;
    },
  };
  const context = {
    AWAKE_MP4: "mp4",
    AWAKE_WEBM: "webm",
    Math: { random: () => 0.2 },
    document,
    navigator,
    setTimeout(callback) {
      timers.push(callback);
    },
    window: {
      addEventListener(type, callback) {
        windowListeners[type] = callback;
      },
    },
  };
  vm.runInNewContext(script, context);
  return { documentListeners, muted: () => mutedAssigned, timers, videos, windowListeners };
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

async function run() {
  const locks = [];
  const native = environment({
    wakeLock: {
      async request() {
        const listeners = {};
        const lock = {
          released: false,
          addEventListener(type, callback) {
            listeners[type] = callback;
          },
          listeners,
        };
        locks.push(lock);
        return lock;
      },
    },
  });

  native.windowListeners.load();
  await flush();
  assert.strictEqual(locks.length, 1);

  native.documentListeners.pointerdown();
  await flush();
  assert.strictEqual(locks.length, 1);

  locks[0].released = true;
  locks[0].listeners.release();
  assert.strictEqual(native.timers.length, 1);
  native.timers.shift()();
  await flush();
  assert.strictEqual(locks.length, 2);

  const fallback = environment({});
  fallback.documentListeners.pointerdown();
  await flush();
  assert.strictEqual(fallback.videos.length, 1);
  assert.strictEqual(fallback.videos[0].paused, false);
  assert.strictEqual(fallback.muted(), false);

  const video = fallback.videos[0];
  video.duration = 2;
  video.listeners.loadedmetadata();
  video.currentTime = 0.75;
  video.listeners.timeupdate();
  assert.strictEqual(video.currentTime, 0.2);
}

run().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
