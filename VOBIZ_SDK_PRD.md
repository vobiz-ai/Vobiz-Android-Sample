# Product Requirements Document
## Vobiz WebRTC SDK — Voice Calling Platform

**Version:** 1.2
**Date:** 2026-04-20
**Author:** Dheeraj (dheeraj@vobiz.ai)
**Status:** Live / Active Development

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Goals & Success Metrics](#3-goals--success-metrics)
4. [Scope](#4-scope)
5. [System Architecture](#5-system-architecture)
6. [Project Structure](#6-project-structure)
7. [Feature Specifications](#7-feature-specifications)
8. [API Reference](#8-api-reference)
9. [Data Models](#9-data-models)
10. [Flutter SDK Package](#10-flutter-sdk-package)
11. [Environment & Configuration](#11-environment--configuration)
12. [Setup & Deployment](#12-setup--deployment)
13. [Security Considerations](#13-security-considerations)
14. [Known Limitations](#14-known-limitations)
15. [Glossary](#15-glossary)

---

## 1. Executive Summary

The **Vobiz WebRTC SDK** is a full-stack voice calling platform that enables Flutter mobile applications to make and receive phone calls over the internet using SIP/WebRTC, connected to real-world PSTN telephone networks through the Vobiz (Plivo-compatible) telephony infrastructure.

The platform is composed of three layers:

- A **Flutter client SDK** (`packages/vobiz_webrtc`) that handles SIP registration, WebRTC audio, and call lifecycle management
- A **Node.js backend server** (`Vobiz-RTC-demo/server.js`) that acts as the call orchestrator, bridging the Flutter app with the Vobiz REST API
- The **Vobiz cloud infrastructure** that handles PSTN connectivity, SIP routing, and media relay

The SDK supports outbound dialing, inbound call answering, call hold/resume with audio announcements, blind call transfer, consultative (warm) 3-way call transfer, conference add call (instant merge), and second call management with swap and merge (Option B). It is designed as a white-label foundation for building VoIP-enabled mobile applications.

---

## 2. Problem Statement

### 2.1 Background

Traditional telephony integration in mobile apps requires either expensive hardware infrastructure, complex SIP server administration, or vendor-locked SDKs with limited customizability. Developers building call-center-style applications, customer support apps, or VoIP dialers face a steep learning curve combining SIP, WebRTC, and telephony APIs.

### 2.2 The Gap

| Problem | Impact |
|---|---|
| WebRTC ↔ PSTN bridging is complex | Most apps either use WebRTC-only (no real phone calls) or PSTN-only (no in-app audio) |
| Hold is commonly implemented as mute | Callers hear silence; no "you are on hold" announcement |
| Call transfer requires active call re-routing | Most mobile SDK implementations drop the call instead of transferring it |
| Warm (consultative) transfer requires 3-party conferencing | Extremely difficult to implement at the SDK level without server-side orchestration |
| Physical device backend connectivity | `localhost` on a mobile device resolves to the device, not the developer's machine |

### 2.3 What This SDK Solves

The Vobiz SDK provides a pre-built, end-to-end solution for all of the above problems. The backend orchestrates all Vobiz API calls so the Flutter app only needs to call simple methods like `client.hold()`, `client.transfer(dest)`, or `client.warmTransferStart(dest)`. The SIP/WebRTC complexity is encapsulated in the `vobiz_webrtc` package.

---

## 3. Goals & Success Metrics

### 3.1 Primary Goals

| Goal | Description |
|---|---|
| **G1 — Reliability** | Call setup, hold, and transfer must complete successfully ≥ 95% of the time on a stable network |
| **G2 — Developer Experience** | A developer can integrate and place a working call within 30 minutes using this SDK |
| **G3 — Feature Parity** | Match basic call-center features: answer, dial, hold, resume, mute, blind transfer, warm transfer, add call, second call with swap/merge |
| **G4 — White-label Ready** | All branding, colors, and text are customizable at the Flutter widget layer |
| **G5 — Cross-Platform** | Flutter app targets Android (primary), iOS, and Web with a single codebase |

### 3.2 Success Metrics

| Metric | Target |
|---|---|
| Call setup time (dial → ringing) | < 4 seconds on a 4G connection |
| Hold announcement latency | < 2 seconds after hold button tap |
| Blind transfer completion time | < 3 seconds for call redirect |
| Warm transfer conference join time | < 6 seconds for third party to enter conference |
| Audio quality | No subjective echo, clipping, or dropout under normal network conditions |
| SDK bundle size | < 5 MB additional AAR/framework overhead |

---

## 4. Scope

### 4.1 In Scope

- SIP registration and keep-alive over WebSocket (WSS)
- Outbound calls from Flutter app to PSTN phone numbers
- Inbound calls from PSTN to the Flutter app (via SIP endpoint)
- In-call audio controls: mute, unmute
- Call hold with PSTN-side audio announcement (looping TTS)
- Call resume (PSTN rejoins conference)
- Blind (immediate) call transfer to PSTN number or SIP URI
- Warm (consultative) call transfer with 3-way conference, then agent drop-off
- Add Call — Option A: dial a third party directly into the active conference (instant merge)
- Add Call — Option B: start a second separate call, swap between the two, merge, or end either independently
- Call state machine with reactive UI (StreamBuilder-based)
- Backend webhook handling for all Vobiz call lifecycle events
- Demo Flutter application (`apps/vobiz_demo`) showcasing all features

### 4.2 Out of Scope (Current Version)

- Push notification delivery for incoming calls when app is backgrounded
- Call recording
- DTMF (touch-tone) input during calls
- Video calling
- Voicemail
- Conference calls with more than 3 participants (Option B merge creates a 3-party call; beyond 3 is not supported)
- Presence / online status indicators
- Call queue management
- IVR / automated call flows
- Persistent call history or CRM integration
- Multi-tenant or multi-account support

---

## 5. System Architecture

### 5.1 High-Level Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App                              │
│  ┌─────────────┐   ┌──────────────────┐   ┌─────────────────┐  │
│  │  UI Screens │ → │   VobizClient    │ → │  BackendService │  │
│  │  (Widgets)  │   │  (State Machine) │   │  (HTTP calls)   │  │
│  └─────────────┘   └──────────────────┘   └────────┬────────┘  │
│                           │ SIP/WebRTC              │ HTTP      │
└───────────────────────────┼─────────────────────────┼──────────┘
                            │                         │
                  ┌─────────▼───────┐       ┌─────────▼──────────┐
                  │  Vobiz SIP      │       │  Node.js Backend   │
                  │  Infrastructure │       │  server.js :3000   │
                  │  (WSS :5063)    │       │                    │
                  └─────────┬───────┘       └─────────┬──────────┘
                            │                         │ REST API
                            │               ┌─────────▼──────────┐
                            └──────────────▶│  Vobiz REST API    │
                                            │  api.vobiz.ai      │
                                            └─────────┬──────────┘
                                                      │
                                            ┌─────────▼──────────┐
                                            │   PSTN Network     │
                                            │  (Real Phones)     │
                                            └────────────────────┘
```

### 5.2 Conference-Based Calling Architecture

All calls use a named conference room as the audio bridge. This enables per-participant control (hold, transfer) without disrupting other legs.

```
Outbound Call Flow:
──────────────────
1. Flutter app → POST /call → Backend
2. Backend dials PSTN via Vobiz API (answer_url = /conference-join?room=vr_<ts>)
3. Vobiz calls backend → GET /sdk-answer → returns Conference XML (stayAlone="true")
4. SDK leg joins conference room as audio source
5. PSTN call connects → Vobiz hits /conference-join → stores pstnCallUuid
6. Both parties are now in the same named conference room

Inbound Call Flow:
──────────────────
1. PSTN call arrives → Vobiz hits /inbound-answer on backend
2. Backend creates room ID, returns Conference XML to hold PSTN
3. Backend calls SDK's SIP endpoint → SDK app rings
4. User answers → SDK leg joins conference
5. Both parties in the same conference room
```

### 5.3 Hold Architecture

```
Hold:
─────
PSTN leg → redirectCallTo(/hold-loop) → Looping TTS: "Your call is on hold..."
SDK leg  → stays in conference (stayAlone="true" keeps room alive)
Flutter  → mutes local mic, emits CallState.held

Resume:
───────
PSTN leg → redirectCallTo(/conference-join?room=roomId) → rejoins conference
SDK leg  → already in conference, unmutes mic
Flutter  → emits CallState.inCall
```

### 5.4 Add Call Architecture

Both add-call modes use the **same conference room** as the active call — the SDK leg never moves. Only PSTN legs are redirected in and out.

```
Option A — Merge In (instant conference):
──────────────────────────────────────────
Backend  → dials added party into same room (?type=added)
All 3    → SDK + PSTN1 + added party all in conference simultaneously
           → Flutter shows teal "Conference — <number> joined" banner
Agent    → taps Remove → Vobiz DELETE /Call/{addedCallUuid}/ → party dropped
           → returns to normal 2-party call

Option B — New Call (separate, swappable):
───────────────────────────────────────────
Step 1 (start):
  PSTN1 → redirectCallTo(/hold-loop)                   [put on hold]
  PSTN2 → dialSecondCallIntoConference(room, ?type=second)  [dial separately]
  Flutter → hasSecondCall=true, firstCallActive=false

Step 2 (swap):
  Active leg → redirectCallTo(/hold-loop)
  Held leg   → redirectCallTo(/conference-join?room=...)
  Flutter → firstCallActive toggled

Step 3a (merge):
  Held leg → redirectCallTo(/conference-join?room=...)
  Both PSTN1 + PSTN2 now in conference simultaneously → becomes Conference (Option A state)

Step 3b (end second):
  PSTN2 → vobizHangupCall(secondCallUuid)
  If PSTN1 was held → redirectCallTo(/conference-join?room=...)
  Flutter → hasSecondCall=false, back to normal 2-party call
```

### 5.5 Transfer Architecture

```
Blind Transfer:
───────────────
PSTN leg → redirectCallTo(/transfer-bridge?to=<dest>)
           → Plays "You are being transferred..."
           → <Dial callerId timeout="60"><Number>dest</Number></Dial>
SDK leg  → hangup() locally
Flutter  → emits CallState.transferring → idle

Warm Transfer:
──────────────
Backend  → dials transfer target into same conference room
All 3    → SDK agent + PSTN caller + transfer target in conference
           → Flutter shows "3-way call — consulting transfer target"
Agent    → taps "Complete Transfer" → hangup() locally
Remaining → PSTN caller + transfer target stay in conference
```

---

## 6. Project Structure

```
sdk/
├── vobiz_inbound/                     ← Main full-featured project
│   ├── Vobiz-RTC-demo/
│   │   ├── server.js                  ← Node.js backend (all call orchestration)
│   │   ├── .env                       ← Secrets: API keys, caller ID, public URL
│   │   ├── .env.example               ← Template for environment setup
│   │   └── package.json
│   ├── _zipinspect/
│   │   └── vobiz_flutter/             ← Flutter client (SDK + demo app combined)
│   │       └── lib/
│   │           ├── main.dart          ← App entry point, screen routing
│   │           ├── client/
│   │           │   └── vobiz_client.dart     ← Core SDK: SIP + state machine
│   │           ├── screens/
│   │           │   ├── login_screen.dart     ← SIP credential entry
│   │           │   ├── dialer_screen.dart    ← Phone number input
│   │           │   ├── incoming_screen.dart  ← Incoming call UI
│   │           │   └── incall_screen.dart    ← Active call controls
│   │           └── services/
│   │               └── backend_service.dart  ← HTTP client for server.js
│   ├── apps/
│   │   └── vobiz_demo/               ← Alternate Flutter app (refactored)
│   │       └── lib/
│   │           ├── presentation/
│   │           │   ├── screens/
│   │           │   │   ├── dialer_screen.dart
│   │           │   │   └── active_call_screen.dart
│   │           │   ├── viewmodels/
│   │           │   │   └── call_view_model.dart
│   │           │   └── widgets/
│   │           │       └── call_controls.dart
│   └── packages/
│       └── vobiz_webrtc/             ← Reusable SDK package
│           └── lib/src/
│               ├── calls/
│               │   ├── call_session.dart    ← RTCPeerConnection management
│               │   └── call_actions.dart   ← mute/unmute/hold action helpers
│               ├── sip/
│               │   └── sip_client.dart     ← SIP over WebSocket
│               └── models/
│                   └── call_state.dart     ← Shared state enums
│
├── vobiz_final/                      ← Simplified outbound-only variant
│   └── apps/vobiz_demo/              ← Minimal demo without inbound/transfer
│
└── VOBIZ_SDK_PRD.md                  ← This document
```

---

## 7. Feature Specifications

### 7.1 Feature: SIP Registration

**Description:** The Flutter app registers a SIP identity with the Vobiz registrar over a secure WebSocket connection. Registration is required before placing or receiving calls.

**User Flow:**
1. User opens the app → `LoginScreen` is shown
2. User enters SIP Username, SIP Password, and SIP Server (or uses defaults from `--dart-define`)
3. Taps **Register** → `VobizClient.register()` is called
4. Client connects to WSS endpoint, sends SIP REGISTER
5. On success → `RegistrationState.registered` → `DialerScreen` shown
6. On failure → error snackbar with reason

**Configuration:**
| Env Var | Default | Description |
|---|---|---|
| `VOBIZ_WS_URL` | `wss://registrar.vobiz.ai:5063/` | SIP WebSocket endpoint |
| `VOBIZ_SIP_SERVER` | `registrar.vobiz.ai` | SIP domain for REGISTER URI |

**State Transitions:**
```
idle → registering → registered
                   → unregistered (on failure)
```

---

### 7.2 Feature: Outbound Calling

**Description:** The registered Flutter app initiates a call to a PSTN phone number. The call is bridged via a named conference room.

**User Flow:**
1. User on `DialerScreen` enters a phone number (e.g., `+919876543210`)
2. Taps **Call** → `VobizClient.call(number)` is called
3. `VobizClient` emits `CallState.calling`
4. Backend POSTed at `/call` with `{"to": number}`
5. Backend dials PSTN via Vobiz API, creates conference room `vr_<timestamp>`
6. Vobiz calls `/sdk-answer` on backend → returns Conference XML → SDK joins room
7. PSTN leg rings → on answer, Vobiz calls `/conference-join` → PSTN joins room
8. Flutter emits `CallState.inCall` → `InCallScreen` shown

**Backend Endpoint:** `POST /call`
**Request:** `{ "to": "+919876543210" }`
**Response:** `200 OK` on success, `500` with error message on failure

**Edge Cases:**
- If `activeCall` is already set (ongoing call), backend returns `409 Conflict`
- If PSTN doesn't answer within Vobiz timeout (~60s), conference remains with SDK leg only until hangup

---

### 7.3 Feature: Inbound Call Answering

**Description:** Incoming PSTN calls routed to the SIP endpoint ring the Flutter app. The agent can answer or reject.

**User Flow:**
1. External caller dials the Vobiz number mapped to the SIP endpoint
2. Vobiz hits `/inbound-answer` on backend
3. Backend creates conference room, puts PSTN leg in room, dials SIP endpoint
4. Flutter app receives SIP INVITE → `CallState.incoming` → `IncomingScreen` shown
5. User taps **Answer** → SDK leg joins conference → `CallState.inCall`
6. User taps **Decline** → SIP 486 Busy → PSTN gets busy tone

**Backend Endpoint:** `GET /inbound-answer`
**Response:** Conference XML joining PSTN to room and dialing SIP endpoint

**Caller ID:** `state.callerId` is extracted from SIP `From` header and displayed on `IncomingScreen`

---

### 7.4 Feature: Mute / Unmute

**Description:** Agent mutes or unmutes their local microphone. The PSTN caller continues to hear silence (not a hold announcement).

**User Flow:**
1. On `InCallScreen`, agent taps **Mute** button
2. `VobizClient.mute()` → `setMuted(true)` on `RTCPeerConnection` → emits `isMuted: true`
3. Mute button changes to **Unmute** (blue tint)
4. Agent taps **Unmute** → `VobizClient.unmute()` → `setMuted(false)` → emits `isMuted: false`

**Constraints:**
- Mute is disabled when call is on hold (hold already silences the mic)
- Mute is disabled during transfer states (`isLocked`)
- Mute is local only — remote party is unaware

---

### 7.5 Feature: Call Hold with Audio Announcement

**Description:** Placing a call on hold redirects the PSTN caller to a looping TTS message so they hear "Your call has been placed on hold" instead of silence.

**User Flow:**
1. Agent taps **Hold** on `InCallScreen`
2. `VobizClient.hold()`:
   - Calls `setMuted(true)` locally
   - Emits `CallState.held`
   - Calls `BackendService.holdCall()`
3. Backend: `POST /hold-start`
   - Calls `redirectCallTo(pstnCallUuid, /hold-loop)`
   - Vobiz redirects PSTN leg to `/hold-loop` endpoint
4. `/hold-loop` returns: `<Speak loop="0">Your call has been placed on hold. Please wait while we connect you.</Speak>`
5. PSTN caller hears announcement looping continuously
6. Flutter shows amber "Call on hold" banner

**Resume Flow:**
1. Agent taps **Resume**
2. `VobizClient.resume()`:
   - Calls `setMuted(false)`
   - Emits `CallState.inCall`
   - Calls `BackendService.resumeCall()`
3. Backend: `POST /resume`
   - Calls `redirectCallTo(pstnCallUuid, /conference-join?room=roomId)`
   - PSTN leg redirected back to conference room
4. Both parties reconnected — hold banner disappears

**Technical Note:** The conference stays alive during hold because the SDK leg remains connected with `stayAlone="true"`. Without this attribute, the conference collapses when the PSTN leg leaves.

---

### 7.6 Feature: Blind Call Transfer

**Description:** Agent transfers the PSTN caller to a new number and immediately disconnects. No consultation with the transfer target.

**User Flow:**
1. Agent taps **Transfer** button → transfer panel slides open
2. Agent enters destination (phone number like `+919...` or SIP URI like `sip:user@domain`)
3. Agent taps **Transfer Now (Blind)**
4. `VobizClient.transfer(dest)`:
   - Validates state (`inCall` or `held`)
   - Emits `CallState.transferring`
   - Calls `BackendService.transferCall(dest)`
   - Calls `hangup()` locally
5. Backend: `POST /transfer`
   - Calls `redirectCallTo(pstnCallUuid, /transfer-bridge?to=<dest>)`
   - Clears `activeCall` state
6. `/transfer-bridge` returns XML:
   - `<Speak>` — "You are being transferred. Please hold."
   - `<Dial callerId timeout="60"><Number>dest</Number></Dial>` for PSTN
   - `<Dial callerId timeout="60"><User>sip:dest</User></Dial>` for SIP
   - Fallback `<Speak>` if transfer target doesn't answer
7. Flutter app returns to `DialerScreen` (call ended)

**Destination Detection Logic:**
- Contains `@` → treated as SIP URI → `<User>` element
- Otherwise → treated as phone number → `<Number>` element

---

### 7.7 Feature: Warm (Consultative) Call Transfer

**Description:** Agent brings in a third party for a consultation 3-way call before handing off. The PSTN caller and transfer target stay connected after the agent hangs up.

**User Flow:**
1. Agent taps **Transfer** button → transfer panel opens
2. Agent enters destination number
3. Agent taps **Consult First (Warm)**
4. `VobizClient.warmTransferStart(dest)`:
   - Validates state (`inCall` or `held`)
   - Emits `CallState.warmTransfer`
   - Calls `BackendService.warmTransferStart(dest)`
5. Backend: `POST /warm-transfer/start`
   - Stores `activeCall.warmTargetNumber`
   - Calls `dialWarmTargetIntoConference(dest, roomId)`
   - Vobiz dials `dest` with `answer_url = /conference-join?room=roomId&type=warm`
6. Transfer target answers → Vobiz hits `/conference-join?type=warm` → stores `warmTargetUuid`, joins conference
7. All three parties are now in the same conference:
   - PSTN original caller
   - Flutter agent (SDK leg)
   - Transfer target
8. Flutter shows green "3-way call — consulting transfer target" banner + "Complete Transfer" button
9. Agent taps **Complete Transfer**:
   - `VobizClient.warmTransferComplete()` → validates `warmTransfer` state → calls `hangup()`
10. SDK leg hangs up → leaves conference → PSTN caller and transfer target continue talking
11. Flutter returns to `DialerScreen`

**Alternative:** Agent taps **Cancel & End** → `hangup()` → all three parties disconnected

---

### 7.8 Feature: Active Call Screen UI

**Description:** Full-featured in-call UI with state-aware controls and banners.

**Screen Layout:**
```
┌────────────────────────────────┐
│  [Status Banner]               │ ← amber (hold), blue (transfer), green (warm)
├────────────────────────────────┤
│                                │
│         [Avatar Icon]          │ ← changes color by state
│      +91 9876543210            │ ← callerId
│         In Call                │ ← status text
│                                │
│   [Mute]  [Hold]  [Transfer]   │ ← control row (disabled during transfer)
│                                │
│  ┌──────────────────────────┐  │
│  │  Transfer To:            │  │ ← collapsible panel
│  │  [+91... or sip:...]     │  │
│  │  [Transfer Now] [Consult]│  │
│  │  [Cancel]                │  │
│  └──────────────────────────┘  │
│                                │
│        [End Call]              │
└────────────────────────────────┘
```

**State-Specific UI Variations:**

| State | Avatar Color | Banner | Controls |
|---|---|---|---|
| `inCall` | Dark slate | None | Mute, Hold, Transfer, Add Call, End |
| `held` | Amber/brown | Amber "Call on hold" | Resume, Transfer, End |
| `transferring` | Blue/navy | Blue "Transferring call..." | All disabled |
| `warmTransfer` | Green/dark | Green "3-way call..." | Complete Transfer, Cancel & End |
| `isConference` | Teal/dark | Teal "Conference — <number> joined" | Mute, Hold, Transfer, Remove, End |
| `hasSecondCall` | Orange/dark | Orange "Active: Call N · Call M on hold" | Mute, Hold, Transfer, Swap, End + call cards + Swap/Merge/End 2nd |

**Add Call Panel (opens on Add Call tap):**
```
[Number input field]
[Merge In — Conference]  [New Call — Separate]
[Cancel]
```

**Second Call Controls (shown when `hasSecondCall`):**
```
┌────────────────────────────────────┐
│ 📞 Call 1: +91...    ACTIVE/HOLD  │
│ 📞 Call 2: +91...    HOLD/ACTIVE  │
│  [Swap]    [Merge]   [End 2nd]     │
└────────────────────────────────────┘
```

---

### 7.9 Feature: Add Call — Option A (Merge In)

**Description:** While on an active call, agent dials a third party directly into the conference room. All three parties hear each other immediately.

**User Flow:**
1. Agent taps **Add Call** (4th button) → panel opens with number input
2. Agent enters number → taps **Merge In**
3. `VobizClient.addCall(dest)` → `POST /add-call` → backend calls `dialAddedPartyIntoConference(dest, roomId)` using `?type=added`
4. Third party's phone rings. When they answer, Vobiz hits `/conference-join?type=added` → `addedCallUuid` stored
5. All three (agent, PSTN caller, added party) are now in the conference
6. Flutter emits `isConference: true, addedCallNumber: dest`
7. Teal banner: *"Conference — +91... joined"*
8. 4th button changes to **Remove**
9. Agent taps **Remove** → `VobizClient.removeAddedCall()` → `POST /remove-added-call` → backend calls `vobizHangupCall(addedCallUuid)`
10. Added party dropped, returns to normal 2-party call

**Constraints:**
- Only one added party at a time
- Not available when on hold or in transfer states
- Removes the added party only — does not end the original call

---

### 7.10 Feature: Add Call — Option B (Second Call with Swap/Merge)

**Description:** Agent puts the active call on hold and places a second independent outbound call. Agent can switch (swap) between the two calls, merge them into a 3-way conference, or end the second call and return to the first.

**User Flow:**
1. Agent taps **Add Call** → panel opens → enters number → taps **New Call**
2. `VobizClient.startSecondCall(dest)`:
   - `POST /second-call` → backend redirects PSTN1 to `/hold-loop`, dials PSTN2 into conference with `?type=second`
   - Flutter emits `hasSecondCall: true, firstCallActive: false, secondCallNumber: dest`
3. Orange banner: *"Active: Call 2 · Call 1 on hold"*
4. Two call cards appear showing active/held status
5. 4th button changes to **Swap** shortcut

**Swap:**
- Agent taps **Swap** (button or call card button)
- `VobizClient.swapCalls()` → `POST /swap-calls`
- Backend: active leg → hold-loop, held leg → conference
- `firstCallActive` toggles, banner updates

**Merge:**
- Agent taps **Merge** in the second call controls
- `VobizClient.mergeCalls()` → `POST /merge-calls`
- Backend redirects held leg back into conference → both PSTN legs in room simultaneously
- Flutter transitions to `isConference: true` (same state as Option A)

**End Second Call:**
- Agent taps **End 2nd**
- `VobizClient.endSecondCall()` → `POST /end-second-call`
- Backend hangs up PSTN2; if PSTN1 was on hold, redirects it back to conference
- Flutter returns to normal `inCall` state with PSTN1

**End All:**
- Agent taps **End Call** → `hangup()` → SIP BYE → backend clears entire `activeCall`

**Constraints:**
- Only one second call at a time
- Swap requires both `pstnCallUuid` and `secondCallUuid` to be captured
- If PSTN2 hasn't answered yet when swap is attempted, the `secondCallUuid` is null and swap returns `400`

---

## 8. API Reference

### 8.1 Backend REST Endpoints (server.js)

All endpoints run on `http://localhost:3000` by default. `PUBLIC_URL` must be a publicly accessible URL for Vobiz webhooks.

#### `POST /call`
Initiates an outbound call.

**Request:**
```json
{ "to": "+919876543210" }
```

**Response:** `200 OK` | `409 Conflict` (call in progress) | `500 Internal Server Error`

---

#### `GET /sdk-answer`
Webhook: Vobiz calls this for the SDK SIP leg on outbound calls.

**Response (XML):**
```xml
<Response>
  <Conference stayAlone="true">vr_1713600000000</Conference>
</Response>
```

---

#### `GET /inbound-answer`
Webhook: Vobiz calls this when an inbound PSTN call arrives.

**Response (XML):** Conference join + SIP dial XML

---

#### `GET /conference-join`
Webhook: Called by Vobiz when a leg joins the conference.

**Query Params:** `room=<roomId>`, `type` (optional: `warm` | `added` | `second`)

**Stores based on type:**
| `type` | Field set |
|---|---|
| *(none)* | `pstnCallUuid` |
| `warm` | `warmTargetUuid` |
| `added` | `addedCallUuid` |
| `second` | `secondCallUuid` |

---

#### `POST /hold-start`
Puts the PSTN caller on hold (redirects to looping TTS).

**Response:** `200 OK` | `400` if no active call

---

#### `POST /resume`
Resumes the call from hold (redirects PSTN back to conference).

**Response:** `200 OK` | `400` if no active call

---

#### `GET /hold-loop`
Returns looping TTS XML for hold music substitute.

**Response (XML):**
```xml
<Response>
  <Speak loop="0">Your call has been placed on hold. Please wait while we connect you.</Speak>
</Response>
```

---

#### `POST /transfer`
Performs a blind transfer.

**Request:**
```json
{ "to": "+919876543210" }
```

**Response:** `200 OK` | `400` if no active call

---

#### `GET /transfer-bridge`
Webhook: Vobiz serves this to the PSTN leg during blind transfer.

**Query Params:** `to=<encoded-destination>`

**Response (XML — PSTN number example):**
```xml
<Response>
  <Speak>You are being transferred. Please hold.</Speak>
  <Dial callerId="+911234567890" timeout="60">
    <Number>+919876543210</Number>
  </Dial>
  <Speak>We were unable to connect your transfer. Please try again.</Speak>
</Response>
```

---

#### `POST /warm-transfer/start`
Starts a warm transfer by dialing the target into the conference.

**Request:**
```json
{ "to": "+919876543210" }
```

**Response:** `200 OK` | `400` if no active call or warm transfer already in progress

---

#### `POST /add-call`
Dials a third party into the active conference (Option A — Merge In).

**Request:** `{ "to": "+919876543210" }`

**Response:** `200 OK` | `409 Conflict` (add call already active) | `503` if no active call

---

#### `POST /remove-added-call`
Hangs up the added party (Option A).

**Response:** `200 OK` | `400` if no added call UUID available

---

#### `POST /second-call`
Puts PSTN1 on hold and dials PSTN2 separately (Option B — New Call).

**Request:** `{ "to": "+919876543210" }`

**Response:** `200 OK` | `409 Conflict` (second call already active) | `503` if no active call or `pstnCallUuid` not yet captured

---

#### `POST /swap-calls`
Swaps which call is active vs on hold (Option B).

**Response:** `200 OK` | `400` if both UUIDs not available

---

#### `POST /merge-calls`
Merges held leg back into conference so both legs are active simultaneously (Option B → Option A state).

**Response:** `200 OK` | `400` if both UUIDs not available

---

#### `POST /end-second-call`
Hangs up PSTN2 and resumes PSTN1 if it was on hold (Option B).

**Response:** `200 OK` | `400` if no active call

---

#### `POST /hangup`
Hangs up the current call (clears server state).

**Response:** `200 OK`

---

#### `GET /health`
Health check endpoint.

**Response:** `200 OK` — `{ "status": "ok" }`

---

### 8.2 Vobiz REST API Calls (Made by server.js)

The backend uses the following Vobiz API endpoints:

#### Outbound Dial
```
POST https://api.vobiz.ai/v1/Account/{authId}/Call/
Body:
  to=<number>
  from=<CALLER_ID>
  answer_url=<PUBLIC_URL>/conference-join?room=<roomId>
  answer_method=GET
```

#### Transfer / Redirect Live Call
```
POST https://api.vobiz.ai/v1/Account/{authId}/Call/{callUuid}/
Body:
  aleg_url=<target-url>
  aleg_method=GET
```

**Critical:** The parameter is `aleg_url` / `aleg_method` — NOT `answer_url` / `answer_method`. Using the wrong param names returns `400: aleg_url must be present`.

---

## 9. Data Models

### 9.1 Server — `activeCall` Object

```javascript
{
  roomId: "vr_1713600000000",     // Conference room name (all legs share this)
  sdkCallSid: "CA...",            // Vobiz SID for the SDK leg (if outbound)
  pstnNumber: "+919876543210",    // Original PSTN number
  pstnCallUuid: "abc-123-...",    // UUID of original PSTN leg
  warmTargetNumber: "+91...",     // Warm transfer target (or null)
  warmTargetUuid: "def-456-...",  // UUID of warm target (or null)
  addedCallNumber: "+91...",      // Option A: merged-in party number (or null)
  addedCallUuid: "ghi-789-...",   // Option A: merged-in party UUID (or null)
  secondCallNumber: "+91...",     // Option B: second call number (or null)
  secondCallUuid: "jkl-012-...",  // Option B: second call UUID (or null)
  firstCallActive: true,          // Option B: true = PSTN1 in conf, false = PSTN2 in conf
}
```

**Lifecycle:**
- Created: on `POST /call` or `/inbound-answer`
- `pstnCallUuid` set: when Vobiz hits `/conference-join` (no type)
- `warmTargetUuid` set: when Vobiz hits `/conference-join?type=warm`
- `addedCallUuid` set: when Vobiz hits `/conference-join?type=added`
- `secondCallUuid` set: when Vobiz hits `/conference-join?type=second`
- `firstCallActive` toggled: on every `/swap-calls` call
- Cleared: on `POST /hangup` or `POST /transfer`

**Persistence:** In-memory only — lost on server restart.

---

### 9.2 Flutter — `VobizState`

```dart
class VobizState {
  final RegistrationState registration;
  final CallState call;
  final bool isMuted;
  final bool isHeld;
  final String? callerId;
  final String? errorMessage;
  final bool isConference;        // Option A: third party merged in
  final String? addedCallNumber;  // Option A: number of merged party
  final bool hasSecondCall;       // Option B: second call active
  final String? secondCallNumber; // Option B: second call number
  final bool firstCallActive;     // Option B: which leg is in conference
}
```

#### `RegistrationState` enum

| Value | Meaning |
|---|---|
| `unregistered` | Not connected to SIP server |
| `registering` | REGISTER sent, awaiting response |
| `registered` | Ready to make/receive calls |
| `failed` | Registration failed |

#### `CallState` enum

| Value | Meaning | Screen |
|---|---|---|
| `idle` | No active call | `DialerScreen` |
| `calling` | Outbound INVITE sent | `InCallScreen` |
| `ringing` | Remote is ringing (180 received) | `InCallScreen` |
| `incoming` | Incoming INVITE received | `IncomingScreen` |
| `inCall` | Call connected (200 OK received) | `InCallScreen` |
| `held` | Call on hold | `InCallScreen` |
| `transferring` | Blind transfer in progress | `InCallScreen` |
| `warmTransfer` | 3-way warm transfer active | `InCallScreen` |
| `ended` | Call has ended | → `DialerScreen` |

---

## 10. Flutter SDK Package

### 10.1 `packages/vobiz_webrtc`

The SDK package contains the low-level SIP and WebRTC implementation. It is designed to be used independently of the demo app.

**Key Classes:**

| Class | File | Responsibility |
|---|---|---|
| `VobizClient` | `client/vobiz_client.dart` | Public API: register, call, hangup, hold, mute, transfer |
| `SipClient` | `sip/sip_client.dart` | SIP REGISTER, INVITE, BYE over WebSocket |
| `CallSession` | `calls/call_session.dart` | `RTCPeerConnection`, ICE negotiation, media tracks |
| `CallActions` | `calls/call_actions.dart` | Mute/unmute/hold helpers |
| `BackendService` | `services/backend_service.dart` | HTTP client to `server.js` |

### 10.2 `VobizClient` Public API

```dart
class VobizClient {
  // Lifecycle
  VobizClient({required String wsUrl, required String sipServer});
  void dispose();

  // State
  Stream<VobizState> get stream;
  VobizState get state;

  // Registration
  Future<void> register({required String username, required String password});
  Future<void> unregister();

  // Call control
  Future<void> call(String destination);
  Future<void> answer();
  Future<void> hangup();
  Future<void> mute();
  Future<void> unmute();
  Future<void> hold();
  Future<void> resume();

  // Transfer
  Future<void> transfer(String destination);
  Future<void> warmTransferStart(String destination);
  Future<void> warmTransferComplete();

  // Add Call — Option A (instant conference merge)
  Future<void> addCall(String destination);
  Future<void> removeAddedCall();

  // Add Call — Option B (separate call with swap/merge)
  Future<void> startSecondCall(String destination);
  Future<void> swapCalls();
  Future<void> mergeCalls();
  Future<void> endSecondCall();
}
```

### 10.3 WebRTC Configuration

```dart
final configuration = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ]
};
```

- Audio-only (`offerToReceiveAudio: true`, `offerToReceiveVideo: false`)
- No TURN servers configured (required for symmetric NAT scenarios)
- ICE candidate trickling over SIP INFO messages

---

## 11. Environment & Configuration

### 11.1 Backend `.env` File

Located at `vobiz_inbound/Vobiz-RTC-demo/.env`:

| Variable | Example | Required | Description |
|---|---|---|---|
| `VOBIZ_ACCOUNT_SID` | `MA...` | Yes | Vobiz account identifier |
| `VOBIZ_AUTH_TOKEN` | `abc123...` | Yes | Vobiz API auth token |
| `CALLER_ID` | `+911234567890` | Yes | Outbound caller ID (must be verified) |
| `SIP_ENDPOINT` | `sip:agent@registrar.vobiz.ai` | Yes | SIP URI to ring on inbound calls |
| `PUBLIC_URL` | `https://abc.ngrok.io` | Yes | Publicly accessible URL for webhooks |
| `DEFAULT_DESTINATION` | `+919876543210` | No | Default call target for testing |
| `DEFAULT_COUNTRY_CODE` | `91` | No | Country code prefix for dialing |

### 11.2 Flutter Build-Time Configuration

Passed via `--dart-define` at build/run time:

| Dart Define | Default | Description |
|---|---|---|
| `VOBIZ_WS_URL` | `wss://registrar.vobiz.ai:5063/` | SIP WebSocket URL |
| `VOBIZ_SIP_SERVER` | `registrar.vobiz.ai` | SIP domain |
| `VOBIZ_BACKEND_URL` | `http://127.0.0.1:3000` | Backend server URL |

---

## 12. Setup & Deployment

### 12.1 Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Flutter | ≥ 3.19 | Mobile app framework |
| Dart | ≥ 3.3 | Flutter language |
| Node.js | ≥ 18 | Backend server |
| ngrok / similar | Any | Expose backend for Vobiz webhooks |
| ADB | Any | Android device port forwarding |

### 12.2 Backend Setup

```bash
# Navigate to backend
cd vobiz_inbound/Vobiz-RTC-demo

# Install dependencies
npm install

# Copy and fill environment file
cp .env.example .env
# Edit .env: add VOBIZ_ACCOUNT_SID, VOBIZ_AUTH_TOKEN, CALLER_ID, PUBLIC_URL, etc.

# Start ngrok (in a separate terminal)
ngrok http 3000
# Copy the https URL → set as PUBLIC_URL in .env

# Start backend
node server.js
```

### 12.3 Flutter App Setup

```bash
cd vobiz_inbound/_zipinspect/vobiz_flutter

# Get dependencies
flutter pub get

# Run on Android emulator (uses localhost)
flutter run

# Run on physical Android device
adb reverse tcp:3000 tcp:3000   # Required before every USB reconnect
flutter run --dart-define=VOBIZ_BACKEND_URL=http://127.0.0.1:3000

# Run with custom backend (e.g., production)
flutter run --dart-define=VOBIZ_BACKEND_URL=https://your-backend.example.com

# Build release APK
flutter build apk --dart-define=VOBIZ_BACKEND_URL=https://your-backend.example.com

# Build for iOS
flutter build ios --dart-define=VOBIZ_BACKEND_URL=https://your-backend.example.com
```

### 12.4 ADB Port Forwarding Explained

When running the Flutter app on a **physical Android device** connected via USB, `127.0.0.1:3000` resolves to the phone's own localhost — not the developer's PC. `adb reverse` creates a TCP tunnel:

```
Phone (127.0.0.1:3000) → USB → PC (localhost:3000)
```

This tunnel must be re-established every time the USB cable is reconnected, because ADB reverse rules are session-scoped.

For production, set `VOBIZ_BACKEND_URL` to a real HTTPS URL and this step is not needed.

---

## 13. Security Considerations

### 13.1 Current Security Posture

| Area | Current State | Risk Level |
|---|---|---|
| API credentials | Stored in `.env` file, not committed to git | Low (if `.env` is gitignored) |
| Backend auth | None — all endpoints are open | High (for production) |
| HTTPS | Backend uses HTTP locally; webhooks from Vobiz use HTTPS via ngrok | Medium |
| SIP credentials | Hardcoded in Flutter `LoginScreen` or `--dart-define` | Medium |
| `activeCall` state | In-memory, single-instance | Low (dev only) |
| Phone number validation | No E.164 validation before dialing | Low |

### 13.2 Recommended Hardening for Production

1. **Add backend authentication** — JWT token or API key required for all `/call`, `/transfer`, `/hold-start`, `/resume` endpoints
2. **Rate limiting** — Apply per-IP rate limiting (express-rate-limit) on dialing endpoints to prevent toll fraud
3. **E.164 validation** — Validate and normalize destination numbers before passing to Vobiz API
4. **HTTPS for backend** — Use a proper TLS certificate, not just ngrok, in production
5. **Persistent state** — Use Redis or a database for `activeCall` state so it survives server restarts
6. **Secrets management** — Move API credentials to environment secrets (AWS Secrets Manager, Vault, etc.) — never in code or committed `.env`
7. **Webhook signature verification** — Validate that incoming webhooks are genuinely from Vobiz (if Vobiz provides HMAC signing)
8. **SIP TLS** — Ensure WSS is used (already the case) — do not downgrade to `ws://`

---

## 14. Known Limitations

The following limitations are present in the current implementation. They are documented to set expectations and inform future development priorities.

### 14.1 Critical Limitations

| # | Limitation | Impact | Workaround |
|---|---|---|---|
| L1 | **No push notifications** | App must be in foreground to receive calls | Keep app open; backgrounded calls are missed |
| L2 | **In-memory call state** | Server restart loses `activeCall` — PSTN caller stranded | Restart server only when no calls are active |
| L3 | **Single original call** | Only one original inbound/outbound call at a time. Option B adds a second leg but within the same session. A true multi-line system (e.g. answer a new inbound while on a call) is not supported. | By design for current demo scope |
| L4 | **No TURN servers** | Calls may fail on networks with symmetric NAT (corporate firewalls, some mobile carriers) | Add TURN server credentials to WebRTC config |

### 14.2 Feature Gaps

| # | Limitation | Notes |
|---|---|---|
| L5 | **No call recording** | No API integration for recording SDK or PSTN legs |
| L6 | **No DTMF (touch-tone)** | Models exist in `CallActions` but not wired to UI or SIP INFO messages |
| L7 | **No voicemail** | No missed call handling or voicemail deposit |
| L8 | **No call history** | Calls are not logged locally or remotely |
| L9 | **No video** | Audio-only by design; video track disabled in WebRTC offer |
| L10 | **Max 3 parties** | Conference supports up to 3 (agent + PSTN1 + one added/warm/second party). Beyond 3 is not implemented. |
| L11 | **No presence / status** | No way to see if another agent is online or busy |
| L12 | **No IVR** | No DTMF-triggered automated flows |
| L13 | **No call queue** | Inbound calls go directly to one SIP endpoint |

### 14.3 Quality & Reliability Limitations

| # | Limitation | Notes |
|---|---|---|
| L14 | **Hardcoded HTTP timeout (10s)** | Backend service calls time out at 10s; slow Vobiz API may fail silently |
| L15 | **No retry logic** | Failed `/hold-start`, `/resume`, `/transfer` calls are not retried |
| L16 | **No error feedback on transfer fail** | If transfer bridge times out (60s), Flutter app is already at DialerScreen with no notification |
| L17 | **No call quality metrics** | No WebRTC `getStats()` collection; MOS score unavailable |
| L18 | **No audio device selection** | Defaults to system audio; no earpiece/speaker/Bluetooth toggle |
| L19 | **No background audio** | Flutter app must remain in foreground for audio; backgrounding ends the call on some Android versions |

### 14.4 Development / Ops Limitations

| # | Limitation | Notes |
|---|---|---|
| L20 | **No rate limiting** | `/call` can be hit repeatedly; risk of toll fraud in production |
| L21 | **No auth on backend** | All endpoints are open; no API key or JWT required |
| L22 | **No webhook signature validation** | Any HTTP client can POST to `/conference-join` and spoof call state |
| L23 | **ngrok dependency** | `PUBLIC_URL` must be updated every time ngrok restarts (free tier) |
| L24 | **ADB required for physical device** | `adb reverse` must be run on every USB reconnect during development |
| L25 | **No iOS push entitlement** | `CallKit` / PushKit integration not implemented |

---

## 15. Glossary

| Term | Definition |
|---|---|
| **PSTN** | Public Switched Telephone Network — the traditional phone network |
| **SIP** | Session Initiation Protocol — the signaling protocol used for VoIP calls |
| **WebRTC** | Web Real-Time Communication — browser/mobile standard for peer-to-peer audio/video |
| **WSS** | WebSocket Secure — encrypted WebSocket, used here for SIP transport |
| **Conference Room** | A named virtual room (e.g. `vr_1713600000000`) that holds multiple call legs |
| **SDK Leg** | The WebRTC/SIP call leg originating from the Flutter app |
| **PSTN Leg** | The traditional phone call leg to/from a real phone number |
| **CallUUID** | Vobiz's unique identifier for a specific call leg |
| **Blind Transfer** | Transferring a call to a new destination without consulting them first |
| **Warm Transfer** | Consulting the transfer target in a 3-way call before handing off |
| **`stayAlone`** | Conference XML attribute that keeps the room alive with a single participant |
| **`aleg_url`** | Vobiz Transfer API parameter to redirect a live call leg to a new XML URL |
| **`redirectCallTo()`** | Internal backend function that calls the Vobiz Transfer API |
| **`activeCall`** | In-memory server object tracking the current call's state and UUIDs |
| **`VobizState`** | Immutable Dart state object emitted by `VobizClient`'s stream |
| **`CallState`** | Enum of all possible call lifecycle states in the Flutter app |
| **ngrok** | Tool that creates a public HTTPS tunnel to localhost for webhook testing |
| **ADB reverse** | Android Debug Bridge command to forward device TCP traffic to the PC |
| **Dart-define** | Flutter build-time environment variable mechanism (`--dart-define=KEY=VALUE`) |
| **E.164** | International phone number format: `+<country><number>` |
| **TTS** | Text-to-Speech — used by Vobiz's `<Speak>` XML element |
| **ICE** | Interactive Connectivity Establishment — WebRTC's NAT traversal protocol |
| **TURN** | Traversal Using Relays around NAT — relay server for WebRTC behind strict firewalls |

---

*Document prepared by Dheeraj (dheeraj@vobiz.ai) · Vobiz SDK v1.2 · 2026-04-20*
