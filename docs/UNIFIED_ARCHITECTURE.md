# Auto-Reverse Typo Fixer - Unified Architecture

## Product goal

One Windows installer, one shared Rust correction engine, and
browser integration where supported by browser security policies.

The user must not install two separate desktop applications.
Browser approval may still be required.

## Components

- arf-core: shared correction and validation engine.
- arf-win: Windows runtime, focus protection and diagnostics.
- arf-native-host: internal Native Messaging executable.
- browser/extension-chromium: read-only field classifier.
- Future installer: manages installed components and cleanup.

## Batch 9C.2 - Safety boundary

The native host accepts only the exact health request:

{"kind":"arf.health.v1"}

It returns a fixed diagnostic-only response.

- No correction commands.
- No keyboard hooks or SendInput.
- No clipboard access.
- No text values or keystroke capture.
- Chromium requests nativeMessaging for an explicit health check only; no host registration is installed yet.
- No changes to the Windows Registry.
- No automatic browser-extension installation.

The extension can request a diagnostic health check after host registration. Text correction remains disabled.

## Future Native Messaging registration

Registration must use the official browser-specific mechanism.

Chrome and other Chromium browsers require a native-host manifest
with explicit allowed_origins and a registered Windows path.

No wildcard extension origins.

Firefox requires a separate compatible browser manifest.

Installation and removal must be reversible and user-approved.

## Important security limitations

A successful diagnostic response is not approval to correct text.

The current browser classifier is advisory only. It may
misclassify sensitive or custom fields.

Browser correction remains disabled until origin verification,
field identity, sensitive-field protection, race handling and
end-to-end testing have been completed.