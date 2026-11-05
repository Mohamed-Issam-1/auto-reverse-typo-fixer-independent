"use strict";

const button = document.getElementById("check");
const status = document.getElementById("status");

button.addEventListener("click", () => {
  button.disabled = true;
  status.textContent = "Checking local engine...";

  let settled = false;

  const finish = (message) => {
    if (settled) return;
    settled = true;
    clearTimeout(timeout);
    status.textContent = message;
    button.disabled = false;
  };

  const timeout = setTimeout(() => {
    finish("Unavailable or timed out. Correction remains disabled.");
  }, 5000);

  try {
    chrome.runtime.sendMessage(
      {kind: "arf.native.health.request.v1"},
      (response) => {
        const error = chrome.runtime.lastError;

        if (
          !error &&
          response &&
          response.ok === true &&
          response.status === "connected"
        ) {
          finish("CONNECTED - diagnostic host only.");
        } else {
          finish("UNAVAILABLE - host not connected.");
        }
      }
    );
  } catch (_) {
    finish("UNAVAILABLE - connection failed.");
  }
});