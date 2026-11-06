"use strict";

// Diagnostic-only field classification and explicit native health check.
const VALID = new Set([
  "NONE", "UNKNOWN", "BLOCK", "TEXT_CANDIDATE"
]);

const LABEL = {
  NONE: "-",
  UNKNOWN: "?",
  BLOCK: "STOP",
  TEXT_CANDIDATE: "TEXT"
};

chrome.runtime.onMessage.addListener((message, sender) => {
  const tabId = sender.tab && sender.tab.id;

  if (!Number.isInteger(tabId) || sender.frameId !== 0) {
    return;
  }

  const url = String(sender.url || "");

  if (!/^(https?:|file:)/.test(url)) {
    return;
  }

  if (
    !message ||
    message.kind !== "arf.field-state.v1" ||
    Object.keys(message).length !== 2 ||
    !VALID.has(message.state)
  ) {
    return;
  }

  chrome.action.setBadgeText({
    tabId,
    text: LABEL[message.state]
  }).catch(() => {});

  chrome.action.setBadgeBackgroundColor({
    tabId,
    color: "#374151"
  }).catch(() => {});

  chrome.action.setTitle({
    tabId,
    title: `ARF read-only: ${message.state} (no correction)`
  }).catch(() => {});
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading") {
    chrome.action.setBadgeText({
      tabId,
      text: "?"
    }).catch(() => {});
  }
});

// Health requests are accepted ONLY from our extension popup.
// Website/content-script messages cannot trigger native messaging.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.kind !== "arf.native.health.request.v1") {
    return false;
  }

  const trusted =
    sender &&
    sender.id === chrome.runtime.id &&
    sender.url === chrome.runtime.getURL("popup.html") &&
    !sender.tab &&
    Object.keys(message).length === 1;

  if (!trusted) {
    sendResponse({ok: false, status: "rejected"});
    return false;
  }

  try {
    chrome.runtime.sendNativeMessage(
      "com.autoreversetypofixer.health",
      {kind: "arf.health.v1"},
      (response) => {
        const valid =
          !chrome.runtime.lastError &&
          response &&
          typeof response === "object" &&
          !Array.isArray(response) &&
          Object.keys(response).length === 3 &&
          response.kind === "arf.health.v1" &&
          response.status === "diagnostic-only" &&
          response.correction_enabled === false;

        sendResponse({
          ok: Boolean(valid),
          status: valid ? "connected" : "unavailable"
        });
      }
    );
    return true;
  } catch (_) {
    sendResponse({ok: false, status: "unavailable"});
    return false;
  }
});