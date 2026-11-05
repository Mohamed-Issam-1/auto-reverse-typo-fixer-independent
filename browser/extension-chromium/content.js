"use strict";

// No input, keydown, keyup, clipboard or text-value listeners.
(() => {
  const classifier = globalThis.ARFFieldClassifier;
  if (!classifier) return;

  let last = null;

  const publish = () => {
    const state = classifier.fieldState(document.activeElement);

    if (state === last) return;
    last = state;

    try {
      const pending = chrome.runtime.sendMessage({
        kind: "arf.field-state.v1",
        state
      });

      if (pending && typeof pending.catch === "function") {
        pending.catch(() => {});
      }
    } catch (_) {
      // Extension may have been reloaded. No action is taken.
    }
  };

  document.addEventListener("focusin", publish, true);

  document.addEventListener(
    "focusout",
    () => queueMicrotask(publish),
    true
  );

  window.addEventListener("pageshow", publish);
  window.addEventListener("focus", publish);

  publish();
})();