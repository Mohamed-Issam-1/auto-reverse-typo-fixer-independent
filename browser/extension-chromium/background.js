"use strict";

// Diagnostic only: no native messaging, storage or networking.
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