"use strict";

const fs = require("node:fs");
const vm = require("node:vm");
const assert = require("node:assert/strict");

const context = {};

vm.runInNewContext(
  fs.readFileSync(__dirname + "/classifier.js", "utf8"),
  context
);

const classify = context.ARFFieldClassifier.fieldState;

function field(tagName, attributes = {}, options = {}) {
  return {
    tagName,
    isContentEditable: !!options.editable,
    disabled: !!options.disabled,
    readOnly: !!options.readOnly,
    getAttribute(key) {
      return attributes[key] || null;
    },
    closest(key) {
      if (key === "form" && options.hasPasswordSibling) {
        return { querySelector() { return {}; } };
      }
      return null;
    }
  };
}

const cases = [
  ["text", field("INPUT", {type:"text"}), "TEXT_CANDIDATE"],
  ["search", field("INPUT", {type:"search"}), "TEXT_CANDIDATE"],
  ["password", field("INPUT", {type:"password"}), "BLOCK"],
  ["OTP autocomplete", field("INPUT",
    {autocomplete:"one-time-code"}), "BLOCK"],
  ["OTP id", field("INPUT", {id:"otpCode"}), "BLOCK"],
  ["numeric OTP", field("INPUT",
    {inputmode:"numeric"}), "BLOCK"],
  ["credit card", field("INPUT",
    {autocomplete:"cc-number"}), "BLOCK"],
  ["login form", field("INPUT", {type:"text"},
    {hasPasswordSibling:true}), "BLOCK"],
  ["readonly", field("INPUT", {type:"text"},
    {readOnly:true}), "BLOCK"],
  ["textarea", field("TEXTAREA"), "TEXT_CANDIDATE"],
  ["contenteditable", field("DIV", {},
    {editable:true}), "TEXT_CANDIDATE"],
  ["button", field("BUTTON"), "UNKNOWN"],
  ["no focus", null, "NONE"]
];

for (const [name, element, expected] of cases) {
  assert.equal(classify(element), expected, name);
  console.log(`PASS ${name}: ${expected}`);
}

console.log(`BROWSER_CLASSIFIER_TESTS_PASS=${cases.length}`);