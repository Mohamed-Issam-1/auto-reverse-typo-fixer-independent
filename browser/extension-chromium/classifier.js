"use strict";

// Advisory classification only. Never authorizes text injection.
(() => {
  const sensitivePattern =
    /(otp|2fa|mfa|one.?time|passw|passcode|secret|token|verif|auth.?code|security.?code|cvv|cvc|credit.?card|\bpin\b)/i;

  const sensitiveAutocomplete =
    /(one-time-code|password|cc-|webauthn)/i;

  const inputTextTypes = new Set(["text", "search"]);

  function fieldState(element) {
    if (!element || typeof element.getAttribute !== "function") {
      return "NONE";
    }

    const tag = String(element.tagName || "").toLowerCase();
    const get = (name) => String(element.getAttribute(name) || "");

    if (
      element.disabled ||
      element.readOnly ||
      get("aria-disabled") === "true"
    ) {
      return "BLOCK";
    }

    const attributes = [
      "id", "name", "aria-label", "autocomplete", "inputmode"
    ];

    if (
      attributes.some((name) => sensitivePattern.test(get(name))) ||
      sensitiveAutocomplete.test(get("autocomplete"))
    ) {
      return "BLOCK";
    }

    if (tag === "input") {
      const type = get("type").toLowerCase() || "text";

      if (
        ["password", "hidden", "number", "tel",
         "email", "date", "time"].includes(type)
      ) {
        return "BLOCK";
      }

      if (!inputTextTypes.has(type)) {
        return "UNKNOWN";
      }

      const mode = get("inputmode").toLowerCase();

      if (["numeric", "decimal", "tel"].includes(mode)) {
        return "BLOCK";
      }

      if (typeof element.closest === "function") {
        const form = element.closest("form");

        if (
          form &&
          typeof form.querySelector === "function" &&
          form.querySelector('input[type="password"]')
        ) {
          return "BLOCK";
        }
      }

      return "TEXT_CANDIDATE";
    }

    if (tag === "textarea") {
      return "TEXT_CANDIDATE";
    }

    if (element.isContentEditable === true) {
      return "TEXT_CANDIDATE";
    }

    return "UNKNOWN";
  }

  globalThis.ARFFieldClassifier =
    Object.freeze({ fieldState });
})();