# Vobiz Flutter — SIP & WebRTC Voice Calling Sample

This repository is a complete [Vobiz](https://vobiz.ai) voice-calling sample that demonstrates
**inbound and outbound voice calling from a Flutter app over SIP and WebRTC**. The Flutter client
registers as a SIP endpoint on `registrar.vobiz.ai`, carries audio over WebRTC, and is paired with a
small Node backend that serves the Vobiz Answer URL XML — so outbound calls reach the PSTN and
inbound calls to your Vobiz number ring inside the app.

---

## Repository layout

| Folder | Purpose |
| --- | --- |
| `vobiz_inbound/` | Full setup for both outbound and inbound calling (the main project) |
| `vobiz_inbound/Vobiz-RTC-demo/` | Node backend (Answer URL XML server) plus an optional browser test client |
| `vobiz_inbound/packages/vobiz_webrtc/` | Reusable Flutter SIP/WebRTC SDK package (`vobiz_webrtc`) |
| `vobiz_inbound/apps/vobiz_demo/` | Flutter demo app wired to the `vobiz_webrtc` package |
| `VOBIZ_SDK_PRD.md` | Product/requirements notes for the SDK scaffold |

---

## Inbound vs outbound (simple meaning)

### Outbound calling

The user starts a call from the app to a destination number.

1. App registers its SIP endpoint
2. User dials a number
3. App calls the backend `POST /call`
4. App sends a SIP `INVITE`
5. Vobiz hits your `/answer` URL
6. Backend returns `<Dial><Number>...</Number></Dial>`
7. Call is bridged to the PSTN

### Inbound calling

Someone dials your Vobiz number and your app receives the call.

1. App must already be SIP-registered
2. PSTN caller dials your Vobiz number
3. Vobiz hits your `/answer` URL
4. Backend returns `<Dial><User>sip:...@registrar.vobiz.ai</User></Dial>`
5. App gets an incoming SIP `INVITE`
6. User accepts or rejects
7. On accept, media starts

---

## What the Flutter demo app does (`vobiz_inbound/apps/vobiz_demo`)

Main responsibilities:

- SIP login and registration
- Outbound call setup
- Incoming call handling UI
- WebRTC media setup (mic, SDP, ICE)
- Call state transitions and error handling

Key runtime pieces:

| Path | Role |
| --- | --- |
| `lib/integration/sdk_factory.dart` | Builds `VobizClient` with the registrar WebSocket and backend URLs |
| `lib/presentation/viewmodels/` | SDK and call view models driving the UI |
| `lib/presentation/screens/` | Splash, login, dialer, incoming call and active call screens |
| `lib/services/fcm_service.dart` | Firebase Cloud Messaging token handling for inbound wake-up |

## What the SDK package is (`vobiz_inbound/packages/vobiz_webrtc`)

A modular, reusable SDK layer that the demo app consumes. It provides:

- The `VobizClient` API and `SdkConfig`
- SIP signalling over WebSocket (`src/signaling/sip_service.dart`)
- WebRTC offer/answer and ICE handling (`src/webrtc/peer_service.dart`)
- Event streams: `connectionEvents`, `callEvents`, `mediaEvents`, `errorEvents`
- Call actions: `connect`, make / accept / reject / hangup, mute / unmute

See `packages/vobiz_webrtc/README.md`, `API_REFERENCE.md`, `CREDENTIALS.md` and `PLATFORM_SETUP.md`
for the package-level details.

## Backend behaviour (`vobiz_inbound/Vobiz-RTC-demo`)

Core endpoints:

| Endpoint | Purpose |
| --- | --- |
| `POST /call` | Store the outbound destination |
| `GET\|POST /answer` | Return the routing XML |
| `GET\|POST /hangup` | Return empty XML |
| `POST /register-token` | Store a username / push-token pair (in memory) |

The server also implements call-control routes used by the demo app — `/conference`,
`/hold-start`, `/resume`, `/transfer`, `/warm-transfer/start`, `/add-call`, `/second-call`,
`/swap-calls`, `/merge-calls` and the matching status webhooks.

In `vobiz_inbound`, `/answer` chooses the flow:

- Outbound SDK leg → returns `<Dial><Number>`
- Inbound PSTN leg → returns `<Dial><User>` using `SIP_ENDPOINT`

---

## What you need from Vobiz

- A Vobiz number (`CALLER_ID`)
- SIP endpoint credentials (username / password) from **Voice → Endpoints**
- The SIP endpoint URI (`sip:<user>@registrar.vobiz.ai`)
- A Voice Application with:
  - Answer URL: `https://<public-url>/answer`
  - Hangup URL: `https://<public-url>/hangup`
- Your number linked to that application

### Prerequisites

1. Node.js 18+ and npm
2. Flutter SDK 3.19+ (Dart 3.3+)
3. Android SDK / iOS toolchain
4. A physical device for call and media testing
5. ngrok (or any public tunnel) for the webhook URLs

### Required `.env` (for the `Vobiz-RTC-demo` backend)

Copy `.env.example` to `.env` and fill in real values:

```env
CALLER_ID=+<your-vobiz-number>
SIP_ENDPOINT=sip:<your-endpoint-username>@registrar.vobiz.ai
DEFAULT_DESTINATION=+<optional-test-number>
DEFAULT_COUNTRY_CODE=91

# Optional — enables the hold announcement
VOBIZ_ACCOUNT_SID=<your-vobiz-account-sid>
VOBIZ_AUTH_TOKEN=<your-vobiz-auth-token>
PUBLIC_URL=https://<your-ngrok-url>
```

- `CALLER_ID` — outbound caller ID used in `<Dial callerId="...">`
- `SIP_ENDPOINT` — where inbound PSTN calls are routed (`<Dial><User>...`)
- `DEFAULT_DESTINATION` — fallback outbound destination when none is posted

---

## Running it

### Terminal 1 — backend

```bash
cd vobiz_inbound/Vobiz-RTC-demo
npm install
npm start
```

The backend listens on port `3000`.

### Terminal 2 — public webhook tunnel

```bash
ngrok http 3000
```

Then set these in the Vobiz Console:

- Answer URL: `https://<ngrok-url>/answer`
- Hangup URL: `https://<ngrok-url>/hangup`

### Terminal 3 — Flutter app

```bash
cd vobiz_inbound/apps/vobiz_demo
flutter pub get
flutter devices
adb reverse tcp:3000 tcp:3000
flutter run -d <device-id> \
  --dart-define=VOBIZ_BACKEND_URL=http://127.0.0.1:3000 \
  --dart-define=VOBIZ_CALLER_ID=+<your-vobiz-number>
```

Supported dart-defines: `VOBIZ_BACKEND_URL`, `VOBIZ_ANSWER_URL`, `VOBIZ_CALLER_ID`.
The client connects to `wss://registrar.vobiz.ai:5063/` with SIP server `registrar.vobiz.ai`.

### Terminal 4 — optional web demo client

```bash
cd vobiz_inbound/Vobiz-RTC-demo
npm run client
```

Open `http://localhost:8080`.

---

## Testing both directions

1. Start the backend and the tunnel.
2. Start the app and log in with your Vobiz endpoint credentials.
3. **Outbound test** — enter an E.164 number in the app, tap Call, and confirm the backend logs show `POST /call` followed by `/answer`.
4. **Inbound test** — keep the app registered and online, dial your Vobiz number from an external phone, confirm the incoming call screen appears, accept, and verify audio.

## Push notifications (inbound wake-up)

- The backend exposes `POST /register-token` and keeps tokens in the in-memory `registeredPushTokens` map.
- FCM dispatch runs through the Firebase Admin SDK: drop a `serviceAccountKey.json` into `Vobiz-RTC-demo/` to enable it, and the backend pushes an `inbound_call` data message to registered devices.
- The Flutter demo app registers its token via `lib/services/fcm_service.dart` (`firebase_messaging`).
- Inbound ringing works whenever the app is connected and SIP-registered; push wake-up covers the backgrounded case once Firebase credentials are in place.

## Safety and operational notes

1. Do not commit `.env`, `serviceAccountKey.json` or any real credentials — they are already git-ignored.
2. Do not commit real phone numbers or ngrok URLs.
3. Keep the caller ID and the destination different (self-calls are blocked).
4. Use physical devices for reliable WebRTC audio tests.

---

## Built by Team Vobiz

[Vobiz](https://vobiz.ai) is a programmable voice & SIP-trunking platform for
voice APIs, SIP trunking, and AI voice agents. This repository is built and
maintained by the Vobiz team.

**Maintainer:** Piyush Sahoo — [piyush@vobiz.ai](mailto:piyush@vobiz.ai) · [LinkedIn](https://www.linkedin.com/in/piyush-s713/)

Questions, or want to talk through an integration? Open an issue on this repo,
or reach out directly at [piyush@vobiz.ai](mailto:piyush@vobiz.ai).

**Useful links:** [Docs](https://docs.vobiz.ai) · [API reference](https://docs.vobiz.ai/api-reference) · [Sign up](https://vobiz.ai)

## License

[MIT](./LICENSE) © Vobiz
