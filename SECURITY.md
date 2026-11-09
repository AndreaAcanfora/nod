# Security

nod approves actions in your name, so security reports are the most welcome
kind of bug report.

**Report privately** through GitHub's
[private vulnerability reporting](https://github.com/AndreaAcanfora/nod/security/advisories/new).
Please do not open a public issue for something exploitable.

## What nod protects

- **The phone's key.** Created on the phone, stored in the Android Keystore or
  iOS Keychain, excluded from backups and device transfer. The gateway only
  ever receives the public key.
- **Answers.** Each answer is an ES256 JWS over the interaction ID, the
  decision, the form data, the device ID and the time. A stolen device token
  without the key cannot answer.
- **Confirmation.** Approving and sending forms ask for biometrics or the
  screen lock (when the phone has one). Declining does not.
- **Privacy.** Push messages carry only an interaction ID and its type; the content stays
  between the phone and your gateway.

## What it does not protect against (yet)

- A compromised phone (root, malware with accessibility access).
- A malicious gateway: it shows you the requests, so it could show you one
  text and give the agent another. The signature covers the interaction ID and
  your decision, not the text you saw. Signing a hash of the displayed request
  is on the roadmap.
- The biometric check is enforced by the app, not bound to the key. Keys in
  StrongBox / Secure Enclave with per-use authentication are on the roadmap.
