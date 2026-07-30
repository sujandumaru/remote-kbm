const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const html = fs.readFileSync("client/index.html", "utf8");
const start = html.indexOf('const kb = document.getElementById("kb")');
const end = html.indexOf("const AWAKE_WEBM", start);
assert(start >= 0 && end > start, "keyboard script not found");

function element(dataset = {}) {
  const classes = new Set();
  return {
    classList: {
      contains: name => classes.has(name),
      remove: name => classes.delete(name),
      toggle: name => classes.has(name) ? classes.delete(name) : classes.add(name),
    },
    dataset,
    listeners: {},
    value: "",
    addEventListener(type, callback) {
      this.listeners[type] = callback;
    },
    focus() {},
  };
}

const kb = element();
const txtrow = element();
const txt = element();
const clear = element();
const toggle = element();
const enter = element({ k: "enter" });
const ids = { kb, txtrow, txt, clr: clear, kbtoggle: toggle };
const sent = [];
const message = value => JSON.parse(JSON.stringify(value));
const context = {
  document: {
    getElementById(id) {
      return ids[id];
    },
    querySelectorAll(selector) {
      if (selector === ".keys button") return [enter];
      return [];
    },
  },
  send(message) {
    sent.push(message);
  },
  Set,
};

vm.runInNewContext(html.slice(start, end), context);

txt.value = "hello";
txt.listeners.input();
assert.deepStrictEqual(message(sent.at(-1)), { t: "text", s: "hello" });

txt.value = "hello\n";
txt.listeners.input();
assert.deepStrictEqual(message(sent.at(-1)), { t: "key", k: "enter" });
assert.strictEqual(txt.value, "");

txt.value = "world";
txt.listeners.input();
assert.deepStrictEqual(message(sent.at(-1)), { t: "text", s: "world" });

let prevented = false;
txt.listeners.beforeinput({
  inputType: "insertLineBreak",
  preventDefault() { prevented = true; },
});
assert.strictEqual(prevented, true);
assert.deepStrictEqual(message(sent.at(-1)), { t: "key", k: "enter" });
assert.strictEqual(txt.value, "");

txt.value = "mobile";
txt.listeners.input();
const beforeEnter = sent.length;
txt.listeners.keydown({ key: "Enter", preventDefault() {} });
txt.listeners.beforeinput({ inputType: "insertParagraph", preventDefault() {} });
assert.strictEqual(sent.length, beforeEnter + 1);
assert.deepStrictEqual(message(sent.at(-1)), { t: "key", k: "enter" });
assert.strictEqual(txt.value, "");
txt.listeners.keyup({ key: "Enter" });

txt.value = "submit";
txt.listeners.input();
txtrow.listeners.submit({ preventDefault() {} });
assert.deepStrictEqual(message(sent.at(-1)), { t: "key", k: "enter" });
assert.strictEqual(txt.value, "");

txt.value = "again";
txt.listeners.input();
enter.onclick();
assert.deepStrictEqual(message(sent.at(-1)), { t: "key", k: "enter", mods: [] });
assert.strictEqual(txt.value, "");
