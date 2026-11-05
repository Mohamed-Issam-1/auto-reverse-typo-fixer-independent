"use strict";

const fs = require("node:fs");
const vm = require("node:vm");
const assert = require("node:assert/strict");

const listeners = [];
const nativeCalls = [];

let nativeReply = {
  kind: "arf.health.v1",
  status: "diagnostic-only",
  correction_enabled: false
};

const chrome = {
  runtime: {
    id: "test-extension-id",
    lastError: null,
    getURL: (p) => "chrome-extension://test-extension-id/" + p,
    onMessage: {
      addListener: (fn) => listeners.push(fn)
    },
    sendNativeMessage(name, message, callback) {
      nativeCalls.push({name, message});
      callback(nativeReply);
    }
  },
  tabs: {
    onUpdated: {addListener() {}}
  },
  action: {
    setBadgeText: async () => {},
    setBadgeBackgroundColor: async () => {},
    setTitle: async () => {}
  }
};

vm.runInNewContext(
  fs.readFileSync(__dirname + "/background.js", "utf8"),
  {chrome}
);

function dispatch(message, sender) {
  let response;

  for (const listener of listeners) {
    listener(message, sender, (value) => {
      response = value;
    });
  }
  return response;
}

const health = {kind: "arf.native.health.request.v1"};
const popup = {
  id: chrome.runtime.id,
  url: chrome.runtime.getURL("popup.html")
};

let response = dispatch(health, popup);

assert.equal(response.ok, true);
assert.equal(response.status, "connected");
assert.equal(nativeCalls.length, 1);
assert.equal(
  nativeCalls[0].name,
  "com.autoreversetypofixer.health"
);
assert.equal(
  JSON.stringify(nativeCalls[0].message),
  '{"kind":"arf.health.v1"}'
);
console.log("PASS trusted popup health");

response = dispatch(health, {
  id: chrome.runtime.id,
  url: "https://example.test/",
  tab: {id: 1},
  frameId: 0
});
assert.equal(response.ok, false);
assert.equal(nativeCalls.length, 1);
console.log("PASS untrusted webpage rejected");

response = dispatch(
  {...health, text: "must-not-forward"},
  popup
);
assert.equal(response.ok, false);
assert.equal(nativeCalls.length, 1);
console.log("PASS extra payload rejected");

response = dispatch(health, {
  id: "another-extension",
  url: chrome.runtime.getURL("popup.html")
});
assert.equal(response.ok, false);
assert.equal(nativeCalls.length, 1);
console.log("PASS different extension rejected");

nativeReply = {
  kind: "arf.health.v1",
  status: "diagnostic-only",
  correction_enabled: true
};

response = dispatch(health, popup);
assert.equal(response.ok, false);
console.log("PASS unexpected host authorization rejected");

nativeReply = null;
response = dispatch(health, popup);
assert.equal(response.ok, false);
console.log("PASS missing native host response rejected");

const before = nativeCalls.length;
dispatch(
  {kind: "arf.field-state.v1", state: "TEXT_CANDIDATE"},
  {
    id: chrome.runtime.id,
    url: "https://example.test/",
    tab: {id: 7},
    frameId: 0
  }
);
assert.equal(nativeCalls.length, before);
console.log("PASS ordinary field event does not call host");

console.log("NATIVE_HEALTH_BRIDGE_TESTS_PASS=7");