require('dotenv').config();
const http  = require('http');
const https = require('https');
const { URL } = require('url');
const querystring = require('querystring');
const fs   = require('fs');
const path = require('path');

const port               = 3000;
const callerId           = process.env.CALLER_ID            || ''; 
const sipEndpoint        = process.env.SIP_ENDPOINT;
const defaultDestination = process.env.DEFAULT_DESTINATION;
const defaultCountryCode = process.env.DEFAULT_COUNTRY_CODE || '91';

// Vobiz REST API credentials (from Vobiz dashboard → Settings → API Keys)
// Required for hold announcement feature; falls back to silent hold without them.
const vobizAccountSid = (process.env.VOBIZ_ACCOUNT_SID || '').trim();
const vobizAuthToken  = (process.env.VOBIZ_AUTH_TOKEN  || '').trim();
// Your ngrok / public HTTPS URL (e.g. https://abc123.ngrok.io)
// Required for conference + hold announcement to work.
const publicUrl = (process.env.PUBLIC_URL || '').trim().replace(/\/$/, '');

// ---------------------------------------------------------------------------
// Runtime state
// ---------------------------------------------------------------------------

let lastDialedNumber = null;
const registeredPushTokens = new Map();

// ---------------------------------------------------------------------------
// Firebase Admin SDK — for FCM push notifications
// ---------------------------------------------------------------------------

const admin = require('firebase-admin');
let firebaseInitialized = false;
try {
    const serviceAccount = require('./serviceAccountKey.json');
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    firebaseInitialized = true;
    console.log('[FCM] Firebase Admin initialized');
} catch (e) {
    console.warn('[FCM] Firebase Admin init failed (push notifications disabled):', e.message);
}

async function sendFcmPush(caller, backendUrl, roomId) {
    if (!firebaseInitialized) return;
    const entries = [...registeredPushTokens.values()];
    if (entries.length === 0) { console.log('[FCM] No registered tokens'); return; }
    for (const entry of entries) {
        const token = typeof entry === 'object' ? entry.token : entry;
        const deviceUrl = (typeof entry === 'object' && entry.backendUrl) ? entry.backendUrl : (backendUrl || 'http://10.0.2.2:3000');
        try {
            const data = { 
                type: 'inbound_call', 
                caller: String(caller || ''), 
                backend_url: deviceUrl 
            };
            if (roomId) data.room_id = roomId;
            await admin.messaging().send({
                token,
                data,
                android: { priority: 'high', ttl: 30000 },
            });
            console.log('[FCM] Push sent for inbound call from', caller, roomId ? `(room: ${roomId})` : '');
        } catch (e) {
            console.error('[FCM] Push failed:', e.message);
        }
    }
}

// Legacy conference state (used by the "add-call / merge" flow)
const conferenceRooms = new Map();
const callToRoom      = new Map();

// Active call state
// Shape: { roomId, sdkCallSid, pstnNumber, pstnCallUuid, warmTargetNumber, warmTargetUuid,
//          addedCallNumber, addedCallUuid,
//          secondCallNumber, secondCallUuid, firstCallActive }
// pstnCallUuid    — original PSTN caller's UUID (captured at /conference-join)
// warmTargetUuid  — warm-transfer target's UUID  (captured at /conference-join?type=warm)
// addedCallUuid   — merged add-call party's UUID (captured at /conference-join?type=added)
// secondCallUuid  — Option-B second call UUID    (captured at /conference-join?type=second)
// firstCallActive — true = PSTN1 is in conf, false = PSTN2 is in conf (Option B only)
let activeCall = null;

// ---------------------------------------------------------------------------
// Vobiz REST API helpers
// ---------------------------------------------------------------------------

/**
 * Authenticated request to Vobiz (Plivo-compatible) REST API.
 * method defaults to POST; pass 'GET' for reads, 'DELETE' for stop-speak etc.
 */
function vobizApi(apiPath, params, method = 'POST') {
    return new Promise((resolve, reject) => {
        if (!vobizAccountSid || !vobizAuthToken) {
            return reject(new Error(
                'VOBIZ_ACCOUNT_SID / VOBIZ_AUTH_TOKEN not set — hold announcement unavailable'
            ));
        }

        // Only POST/PUT send a body; GET and DELETE do not.
        const postData = (method === 'POST' || method === 'PUT') && params
            ? (typeof params === 'string' ? params : new URLSearchParams(params).toString())
            : '';

        const auth = Buffer.from(`${vobizAccountSid}:${vobizAuthToken}`).toString('base64');

        const headers = {
            'Authorization': `Basic ${auth}`,
        };
        if (postData) {
            headers['Content-Type']   = 'application/x-www-form-urlencoded';
            headers['Content-Length'] = Buffer.byteLength(postData);
        }

        const options = {
            hostname: 'api.vobiz.ai',
            path:     `/api/v1${apiPath}`,
            method,
            headers,
        };

        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', d => body += d);
            res.on('end', () => {
                console.log(`[vobiz-api] ${res.statusCode} ${method} ${apiPath}`);
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try { resolve(JSON.parse(body)); } catch { resolve(body); }
                } else {
                    reject(new Error(`Vobiz API ${res.statusCode}: ${body.substring(0, 300)}`));
                }
            });
        });
        req.on('error', reject);
        if (postData) req.write(postData);
        req.end();
    });
}

/**
 * Outbound-dial the PSTN number into a named conference room.
 * Vobiz uses Plivo-compatible lowercase snake_case parameters.
 */
function dialPstnIntoConference(pstnNumber, roomId) {
    return vobizApi(`/Account/${vobizAccountSid}/Call/`, {
        to:             pstnNumber,
        from:           callerId,
        answer_url:     `${publicUrl}/conference-join?room=${encodeURIComponent(roomId)}`,
        answer_method:  'GET',
        hangup_url:     `${publicUrl}/pstn-status`,
        hangup_method:  'POST',
    });
}

/**
 * Outbound-dial the warm-transfer target into an existing conference room.
 * Uses ?type=warm so /conference-join stores the UUID separately and doesn't
 * overwrite the original PSTN caller's pstnCallUuid.
 */
function dialWarmTargetIntoConference(targetNumber, roomId) {
    return vobizApi(`/Account/${vobizAccountSid}/Call/`, {
        to:             targetNumber,
        from:           callerId,
        answer_url:     `${publicUrl}/conference-join?room=${encodeURIComponent(roomId)}&type=warm`,
        answer_method:  'GET',
        hangup_url:     `${publicUrl}/pstn-status`,
        hangup_method:  'POST',
    });
}

/**
 * Outbound-dial an Option-B second call into an existing conference room.
 * Uses ?type=second so /conference-join stores the UUID in secondCallUuid.
 */
function dialSecondCallIntoConference(targetNumber, roomId) {
    return vobizApi(`/Account/${vobizAccountSid}/Call/`, {
        to:             targetNumber,
        from:           callerId,
        answer_url:     `${publicUrl}/conference-join?room=${encodeURIComponent(roomId)}&type=second`,
        answer_method:  'GET',
        hangup_url:     `${publicUrl}/pstn-status`,
        hangup_method:  'POST',
    });
}

/**
 * Outbound-dial an added party into an existing conference room.
 * Uses ?type=added so /conference-join stores the UUID in addedCallUuid.
 */
function dialAddedPartyIntoConference(targetNumber, roomId) {
    return vobizApi(`/Account/${vobizAccountSid}/Call/`, {
        to:             targetNumber,
        from:           callerId,
        answer_url:     `${publicUrl}/conference-join?room=${encodeURIComponent(roomId)}&type=added`,
        answer_method:  'GET',
        hangup_url:     `${publicUrl}/pstn-status`,
        hangup_method:  'POST',
    });
}

/**
 * Hang up a specific call leg by UUID.
 */
function vobizHangupCall(callUuid) {
    return vobizApi(`/Account/${vobizAccountSid}/Call/${callUuid}/`, null, 'DELETE');
}

/**
 * Redirect a live call to a new answer URL.
 * Used to send the PSTN leg to the hold-loop TTS page or back to the conference.
 * Vobiz (Plivo-compatible) Transfer Call: POST /Account/{authId}/Call/{callUuid}/
 */
function redirectCallTo(callUuid, url) {
    // Vobiz (Plivo-compatible) Transfer Call API uses aleg_url / aleg_method.
    return vobizApi(`/Account/${vobizAccountSid}/Call/${callUuid}/`, {
        aleg_url:    url,
        aleg_method: 'GET',
    });
}

/** Returns true when conference-mode call orchestration can be used. */
function canUseConferenceMode() {
    return !!(vobizAccountSid && vobizAuthToken && publicUrl);
}

// ---------------------------------------------------------------------------
// Legacy conference helpers (add-call / merge flow)
// ---------------------------------------------------------------------------

function createConferenceRoom(callId1, callId2) {
    const roomId = `conf_${Date.now()}`;
    conferenceRooms.set(roomId, { callIds: new Set([callId1, callId2]), createdAt: new Date() });
    callToRoom.set(callId1, roomId);
    callToRoom.set(callId2, roomId);
    console.log(`[conference] Room ${roomId} created for calls ${callId1}, ${callId2}`);
    return roomId;
}

function getRoomForCall(callId) {
    return callToRoom.get(callId) || null;
}

function removeCallFromRoom(callId) {
    const roomId = callToRoom.get(callId);
    if (!roomId) return;
    callToRoom.delete(callId);
    const room = conferenceRooms.get(roomId);
    if (room) {
        room.callIds.delete(callId);
        if (room.callIds.size === 0) {
            conferenceRooms.delete(roomId);
            console.log(`[conference] Room ${roomId} closed`);
        }
    }
}

function buildConferenceXml(roomId, cid) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Dial callerId="${escapeXml(cid)}">
        <Conference>${escapeXml(roomId)}</Conference>
    </Dial>
</Response>`;
}

// ---------------------------------------------------------------------------
// General utilities
// ---------------------------------------------------------------------------

function normalizePhoneNumber(value) {
    if (!value) return '';
    return String(value).replace(/[^\d+]/g, '').trim();
}

function formatToE164(value) {
    const normalized = normalizePhoneNumber(value);
    if (!normalized) return '';
    if (normalized.startsWith('+')) return normalized;
    if (normalized.length === 10) return `+${defaultCountryCode}${normalized}`;
    if (normalized.length === 11 && normalized.startsWith('0')) {
        return `+${defaultCountryCode}${normalized.substring(1)}`;
    }
    return `+${normalized}`;
}

function isSameNumber(a, b) {
    const left  = normalizePhoneNumber(a).replace(/^\+/, '');
    const right = normalizePhoneNumber(b).replace(/^\+/, '');
    return left.length > 0 && left === right;
}

function parseBody(req, body) {
    const contentType = String(req.headers['content-type'] || '').toLowerCase();
    if (contentType.includes('application/json')) {
        if (!body.trim()) return {};
        try { return JSON.parse(body); }
        catch (e) { throw new Error(`Invalid JSON body: ${e.message}`); }
    }
    if (!body.trim()) return {};
    return querystring.parse(body);
}

function sendXml(res, xml) {
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/xml');
    res.end(xml);
}

function sendJson(res, statusCode, obj) {
    res.statusCode = statusCode;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(obj));
}

function sendText(res, statusCode, message) {
    res.statusCode = statusCode;
    res.setHeader('Content-Type', 'text/plain');
    res.end(message);
}

function maskSecret(value) {
    const text = String(value || '');
    if (text.length <= 8) return '********';
    return `${text.slice(0, 4)}...${text.slice(-4)}`;
}

function redactSensitiveParams(params) {
    const redacted = {};
    for (const [key, value] of Object.entries(params || {})) {
        redacted[key] = /(password|pass|token|secret)/i.test(key)
            ? maskSecret(value)
            : value;
    }
    return redacted;
}

function escapeXml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

function hasPlaceholder(value) {
    return /<[^>]+>/.test(String(value || ''));
}

function validateCallerId(value) {
    if (!value)               return 'Server misconfigured: CALLER_ID not set.';
    if (hasPlaceholder(value)) return 'Server misconfigured: CALLER_ID still has placeholder markers.';
    return '';
}

function validateSipEndpoint(value) {
    if (!value)                return 'Server misconfigured: SIP_ENDPOINT not set.';
    if (hasPlaceholder(value)) return 'Server misconfigured: SIP_ENDPOINT still has placeholder markers.';
    if (!String(value).startsWith('sip:') || !String(value).includes('@'))
        return 'Server misconfigured: SIP_ENDPOINT must be sip:username@registrar.vobiz.ai';
    return '';
}

function buildEmptyResponseXml() {
    return '<?xml version="1.0" encoding="UTF-8"?><Response></Response>';
}

function buildConfigErrorResponseXml(message) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Speak>${escapeXml(message)}</Speak>
</Response>`;
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------

const server = http.createServer((req, res) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);

    // ── Static files: only the web client in client/ ───────────────────────
    // The path is resolved and must stay inside client/, so a request such as
    // /client/../.env can never read this server's own files (.env holds the
    // Auth Token; serviceAccountKey.json the Firebase key).
    if (req.url.startsWith('/client')) {
        const clientDir = path.join(__dirname, 'client');
        let relative;
        try {
            relative = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/client\/?/, '');
        } catch {
            res.writeHead(400); res.end('Bad request'); return;
        }
        const filePath = path.resolve(clientDir, relative);
        const contentTypes = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.png': 'image/png' };
        const contentType = contentTypes[path.extname(filePath).toLowerCase()];
        if (!filePath.startsWith(clientDir + path.sep) || !contentType) {
            res.writeHead(404); res.end('Not found'); return;
        }
        fs.readFile(filePath, (err, data) => {
            if (err) { res.writeHead(404); res.end('Not found'); return; }
            res.setHeader('Content-Type', contentType);
            res.writeHead(200);
            res.end(data);
        });
        return;
    }

    // ── Collect body then route ─────────────────────────────────────────────
    let body = '';
    req.on('data', chunk => body += chunk.toString());
    req.on('end', async () => {
        const parsedUrl = new URL(req.url, `http://localhost:${port}`);
        const queryParams = Object.fromEntries(parsedUrl.searchParams.entries());

        let bodyParams = {};
        try {
            bodyParams = parseBody(req, body);
        } catch (e) {
            sendText(res, 400, e.message);
            return;
        }

        const params = { ...queryParams, ...bodyParams };
        console.log(`[params] ${JSON.stringify(redactSensitiveParams(params))}`);

        // ── POST /call ─────────────────────────────────────────────────────
        if (req.method === 'POST' && parsedUrl.pathname === '/call') {
            const requestedDestination =
                params.to || params.To || params.destination || params.Destination || '';

            const formattedDestination = formatToE164(requestedDestination);
            if (!formattedDestination) {
                sendText(res, 400, 'No destination found in request body');
                return;
            }

            if (callerId && isSameNumber(formattedDestination, callerId)) {
                sendText(res, 400, 'Destination cannot be same as callerId');
                return;
            }

            lastDialedNumber = formattedDestination;
            activeCall = null; // reset any previous call state
            console.log(`Outbound destination stored: ${lastDialedNumber}`);
            sendJson(res, 200, { success: true, destination: lastDialedNumber });
            return;
        }

        // ── POST /conference  (legacy add-call / merge) ────────────────────
        if (req.method === 'POST' && parsedUrl.pathname === '/conference') {
            const callId1 = String(params.callId1 || params.callid1 || '').trim();
            const callId2 = String(params.callId2 || params.callid2 || '').trim();
            if (!callId1 || !callId2) {
                sendText(res, 400, 'callId1 and callId2 are required');
                return;
            }
            const roomId = createConferenceRoom(callId1, callId2);
            sendJson(res, 200, { success: true, roomId });
            return;
        }

        // ── POST /hold-start  (Flutter presses Hold) ───────────────────────
        // Redirects the live PSTN leg to /hold-loop which loops TTS until resumed.
        if (req.method === 'POST' && parsedUrl.pathname === '/hold-start') {
            console.log('[hold-start] Received, activeCall:', JSON.stringify(activeCall));

            if (activeCall && activeCall.pstnCallUuid) {
                try {
                    const holdUrl = `${publicUrl}/hold-loop`;
                    console.log(`[hold-start] Redirecting PSTN ${activeCall.pstnCallUuid} -> ${holdUrl}`);
                    await redirectCallTo(activeCall.pstnCallUuid, holdUrl);
                    console.log('[hold-start] PSTN redirected to hold-loop ✓');
                } catch (e) {
                    console.error('[hold-start] Redirect failed:', e.message);
                }
            } else {
                console.warn('[hold-start] pstnCallUuid not available yet — mic muted on Flutter side only');
                console.warn('[hold-start] activeCall:', JSON.stringify(activeCall));
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /resume  (Flutter presses Resume) ─────────────────────────
        // Redirects the held PSTN leg back into the conference room.
        if (req.method === 'POST' && parsedUrl.pathname === '/resume') {
            console.log('[resume] Received, activeCall:', JSON.stringify(activeCall));

            if (activeCall && activeCall.pstnCallUuid && activeCall.roomId) {
                try {
                    const rejoinUrl = `${publicUrl}/conference-join?room=${encodeURIComponent(activeCall.roomId)}`;
                    console.log(`[resume] Redirecting PSTN ${activeCall.pstnCallUuid} back -> ${rejoinUrl}`);
                    await redirectCallTo(activeCall.pstnCallUuid, rejoinUrl);
                    console.log('[resume] PSTN redirected back to conference ✓');
                } catch (e) {
                    console.error('[resume] Redirect failed:', e.message);
                }
            } else {
                console.warn('[resume] pstnCallUuid not available — skipping API resume');
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /transfer  (Flutter initiates blind call transfer) ───────────
        // Redirects the live PSTN call to /transfer-bridge which plays a brief
        // message and then dials the new destination (PSTN number or SIP URI).
        // The Flutter SDK leg should call hangup() after this returns.
        if (req.method === 'POST' && parsedUrl.pathname === '/transfer') {
            const to = String(params.to || params.To || '').trim();
            console.log('[transfer] Received, to:', to, 'activeCall:', JSON.stringify(activeCall));

            if (!to) {
                sendJson(res, 400, { error: 'Transfer destination (to) is required' });
                return;
            }
            if (!activeCall || !activeCall.pstnCallUuid) {
                sendJson(res, 503, { error: 'No active transferable call — pstnCallUuid not yet available' });
                return;
            }

            const transferUrl = `${publicUrl}/transfer-bridge?to=${encodeURIComponent(to)}`;
            try {
                await redirectCallTo(activeCall.pstnCallUuid, transferUrl);
                console.log(`[transfer] PSTN ${activeCall.pstnCallUuid} redirected to transfer-bridge ✓`);
                activeCall = null; // SDK will hang up — clear state now
            } catch (e) {
                console.error('[transfer] Redirect failed:', e.message);
                sendJson(res, 500, { error: `Transfer failed: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── GET /transfer-bridge  (Vobiz executes this for the transferred call) ─
        // Plays a brief "transferring" message then dials the final destination.
        // Supports both E.164 numbers and sip: URIs.
        if (parsedUrl.pathname === '/transfer-bridge') {
            const to = parsedUrl.searchParams.get('to') || '';
            console.log(`[transfer-bridge] Bridging call to: ${to}`);

            let dialTarget;
            if (to.toLowerCase().startsWith('sip:')) {
                dialTarget = `<User>${escapeXml(to)}</User>`;
            } else {
                const formatted = formatToE164(to);
                dialTarget = `<Number>${escapeXml(formatted || to)}</Number>`;
            }

            sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Speak>Please hold while we transfer your call.</Speak>
    <Dial callerId="${escapeXml(callerId)}" timeout="60">${dialTarget}</Dial>
    <Speak>We were unable to reach the transfer destination. Goodbye.</Speak>
</Response>`);
            return;
        }

        // ── POST /warm-transfer/start  (Flutter starts a warm/consultative transfer) ─
        // Dials the transfer target into the existing conference so all three
        // parties (SDK agent, PSTN caller, target) can speak together.
        // Agent then presses "Complete Transfer" which just calls hangup() locally —
        // PSTN + target remain in the conference after the agent leaves.
        if (req.method === 'POST' && parsedUrl.pathname === '/warm-transfer/start') {
            const to = String(params.to || params.To || '').trim();
            console.log('[warm-transfer/start] to:', to, 'activeCall:', JSON.stringify(activeCall));

            if (!to) {
                sendJson(res, 400, { error: 'Transfer destination (to) is required' });
                return;
            }
            if (!activeCall || !activeCall.roomId) {
                sendJson(res, 503, { error: 'No active call to transfer' });
                return;
            }
            if (activeCall.warmTargetNumber) {
                sendJson(res, 409, { error: 'Warm transfer already in progress' });
                return;
            }

            const target = to.startsWith('sip:') ? to : formatToE164(to);
            try {
                const result = await dialWarmTargetIntoConference(target, activeCall.roomId);
                const requestUuid = result && (result.request_uuid || result.RequestUUID || '');
                console.log(`[warm-transfer/start] Target dialed into conference, request_uuid: ${requestUuid}`);
                activeCall.warmTargetNumber = target;
                activeCall.warmTargetUuid   = null; // set when target answers /conference-join?type=warm
            } catch (e) {
                console.error('[warm-transfer/start] Failed to dial target:', e.message);
                sendJson(res, 500, { error: `Failed to dial transfer target: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /add-call  (Flutter adds a third party to the conference) ──
        if (req.method === 'POST' && parsedUrl.pathname === '/add-call') {
            const to = String(params.to || params.To || '').trim();
            console.log('[add-call] to:', to, 'activeCall:', JSON.stringify(activeCall));

            if (!to) {
                sendJson(res, 400, { error: 'Destination (to) is required' });
                return;
            }
            if (!activeCall || !activeCall.roomId) {
                sendJson(res, 503, { error: 'No active call to add to' });
                return;
            }
            if (activeCall.addedCallNumber) {
                sendJson(res, 409, { error: 'A call has already been added to this conference' });
                return;
            }

            const target = to.startsWith('sip:') ? to : formatToE164(to);
            try {
                const result = await dialAddedPartyIntoConference(target, activeCall.roomId);
                const requestUuid = result && (result.request_uuid || result.RequestUUID || '');
                console.log(`[add-call] Party dialed into conference, request_uuid: ${requestUuid}`);
                activeCall.addedCallNumber = target;
                activeCall.addedCallUuid   = null; // set when party answers /conference-join?type=added
            } catch (e) {
                console.error('[add-call] Failed to dial party:', e.message);
                sendJson(res, 500, { error: `Failed to add call: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /remove-added-call  (Flutter removes the added party) ──────
        if (req.method === 'POST' && parsedUrl.pathname === '/remove-added-call') {
            console.log('[remove-added-call] activeCall:', JSON.stringify(activeCall));

            if (!activeCall || !activeCall.addedCallUuid) {
                sendJson(res, 400, { error: 'No added call to remove' });
                return;
            }

            try {
                await vobizHangupCall(activeCall.addedCallUuid);
                console.log(`[remove-added-call] Hung up addedCallUuid: ${activeCall.addedCallUuid} ✓`);
                activeCall.addedCallNumber = null;
                activeCall.addedCallUuid   = null;
            } catch (e) {
                console.error('[remove-added-call] Failed:', e.message);
                sendJson(res, 500, { error: `Failed to remove: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /second-call  (Option B: put PSTN1 on hold, dial PSTN2) ───
        if (req.method === 'POST' && parsedUrl.pathname === '/second-call') {
            const to = String(params.to || params.To || '').trim();
            console.log('[second-call] to:', to, 'activeCall:', JSON.stringify(activeCall));

            if (!to) {
                sendJson(res, 400, { error: 'Destination (to) is required' });
                return;
            }
            if (!activeCall || !activeCall.roomId) {
                sendJson(res, 503, { error: 'No active call' });
                return;
            }
            if (!activeCall.pstnCallUuid) {
                sendJson(res, 503, { error: 'pstnCallUuid not yet captured — try again in a moment' });
                return;
            }
            if (activeCall.secondCallNumber) {
                sendJson(res, 409, { error: 'Second call already active' });
                return;
            }

            const target = to.startsWith('sip:') ? to : formatToE164(to);
            try {
                // Hold PSTN1
                await redirectCallTo(activeCall.pstnCallUuid, `${publicUrl}/hold-loop`);
                console.log('[second-call] PSTN1 put on hold ✓');
                // Dial PSTN2 into conference
                const result = await dialSecondCallIntoConference(target, activeCall.roomId);
                const requestUuid = result && (result.request_uuid || result.RequestUUID || '');
                console.log(`[second-call] PSTN2 dialed, request_uuid: ${requestUuid}`);
                activeCall.secondCallNumber = target;
                activeCall.secondCallUuid   = null;    // set when PSTN2 answers
                activeCall.firstCallActive  = false;   // PSTN2 will be active once it answers
            } catch (e) {
                console.error('[second-call] Failed:', e.message);
                sendJson(res, 500, { error: `Failed to start second call: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /swap-calls  (Option B: swap active ↔ held) ────────────────
        if (req.method === 'POST' && parsedUrl.pathname === '/swap-calls') {
            console.log('[swap-calls] activeCall:', JSON.stringify(activeCall));

            if (!activeCall || !activeCall.pstnCallUuid || !activeCall.secondCallUuid) {
                sendJson(res, 400, { error: 'Both call UUIDs must be available to swap' });
                return;
            }

            const roomUrl       = `${publicUrl}/conference-join?room=${encodeURIComponent(activeCall.roomId)}`;
            const roomUrlSecond = `${roomUrl}&type=second`;

            try {
                if (activeCall.firstCallActive) {
                    // PSTN1 active → swap to PSTN2
                    await redirectCallTo(activeCall.pstnCallUuid, `${publicUrl}/hold-loop`);
                    await redirectCallTo(activeCall.secondCallUuid, roomUrlSecond);
                    activeCall.firstCallActive = false;
                } else {
                    // PSTN2 active → swap to PSTN1
                    await redirectCallTo(activeCall.secondCallUuid, `${publicUrl}/hold-loop`);
                    await redirectCallTo(activeCall.pstnCallUuid, roomUrl);
                    activeCall.firstCallActive = true;
                }
                console.log(`[swap-calls] Swapped → firstCallActive: ${activeCall.firstCallActive} ✓`);
            } catch (e) {
                console.error('[swap-calls] Failed:', e.message);
                sendJson(res, 500, { error: `Swap failed: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /merge-calls  (Option B: bring held leg into conference) ───
        if (req.method === 'POST' && parsedUrl.pathname === '/merge-calls') {
            console.log('[merge-calls] activeCall:', JSON.stringify(activeCall));

            if (!activeCall || !activeCall.pstnCallUuid || !activeCall.secondCallUuid) {
                sendJson(res, 400, { error: 'Both call UUIDs must be available to merge' });
                return;
            }

            const roomUrl       = `${publicUrl}/conference-join?room=${encodeURIComponent(activeCall.roomId)}`;
            const roomUrlSecond = `${roomUrl}&type=second`;

            try {
                // Redirect the held leg back into the conference — both now active
                if (activeCall.firstCallActive) {
                    await redirectCallTo(activeCall.secondCallUuid, roomUrlSecond);
                } else {
                    await redirectCallTo(activeCall.pstnCallUuid, roomUrl);
                }
                activeCall.firstCallActive = true; // both are in room
                console.log('[merge-calls] Both legs merged into conference ✓');
            } catch (e) {
                console.error('[merge-calls] Failed:', e.message);
                sendJson(res, 500, { error: `Merge failed: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /end-second-call  (Option B: hang up PSTN2, resume PSTN1) ──
        if (req.method === 'POST' && parsedUrl.pathname === '/end-second-call') {
            console.log('[end-second-call] activeCall:', JSON.stringify(activeCall));

            if (!activeCall) {
                sendJson(res, 400, { error: 'No active call' });
                return;
            }

            try {
                if (activeCall.secondCallUuid) {
                    await vobizHangupCall(activeCall.secondCallUuid);
                    console.log('[end-second-call] PSTN2 hung up ✓');
                }
                // If PSTN1 was on hold, redirect it back to conference
                if (!activeCall.firstCallActive && activeCall.pstnCallUuid) {
                    const roomUrl = `${publicUrl}/conference-join?room=${encodeURIComponent(activeCall.roomId)}`;
                    await redirectCallTo(activeCall.pstnCallUuid, roomUrl);
                    console.log('[end-second-call] PSTN1 resumed ✓');
                }
                activeCall.secondCallNumber = null;
                activeCall.secondCallUuid   = null;
                activeCall.firstCallActive  = true;
            } catch (e) {
                console.error('[end-second-call] Failed:', e.message);
                sendJson(res, 500, { error: `End second call failed: ${e.message}` });
                return;
            }

            sendJson(res, 200, { success: true });
            return;
        }

        // ── GET /hold-loop  (Vobiz executes this XML for the held PSTN leg) ─
        // Loops a TTS message until the Flutter app calls /resume which redirects
        // the PSTN leg back to /conference-join.
        if (parsedUrl.pathname === '/hold-loop') {
            sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Speak loop="0">Your call has been placed on hold. Please wait while we connect you.</Speak>
</Response>`);
            return;
        }

        // ── GET /hold-announcement  (legacy — kept for compatibility) ────────
        if (parsedUrl.pathname === '/hold-announcement') {
            sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Speak loop="0">Your call has been placed on hold. Please wait while we connect you.</Speak>
</Response>`);
            return;
        }

        // ── GET /conference-join  (PSTN or warm-transfer target answers) ──────
        if (parsedUrl.pathname === '/conference-join') {
            const roomId    = parsedUrl.searchParams.get('room') || '';
            const joinType  = parsedUrl.searchParams.get('type') || '';  // 'warm' for transfer target
            const callUuid  = params.CallUUID || params.ALegUUID || '';
            console.log(`[conference-join] type="${joinType}" uuid="${callUuid}" room="${roomId}"`);

            if (activeCall && activeCall.roomId === roomId && callUuid) {
                if (joinType === 'warm') {
                    activeCall.warmTargetUuid = callUuid;
                    console.log(`[conference-join] warmTargetUuid stored: ${callUuid}`);
                } else if (joinType === 'added') {
                    activeCall.addedCallUuid = callUuid;
                    console.log(`[conference-join] addedCallUuid stored: ${callUuid}`);
                } else if (joinType === 'second') {
                    activeCall.secondCallUuid = callUuid;
                    console.log(`[conference-join] secondCallUuid stored: ${callUuid}`);
                } else {
                    activeCall.pstnCallUuid = callUuid;
                    console.log(`[conference-join] pstnCallUuid stored: ${callUuid}`);
                }
            }

            // Plivo/Vobiz: <Conference> directly under <Response> (no <Dial> wrapper)
            sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Conference>${escapeXml(roomId)}</Conference>
</Response>`);
            return;
        }

        // ── POST /conference-status  (Vobiz conference lifecycle events) ───
        if (parsedUrl.pathname === '/conference-status') {
            const event    = params.StatusCallbackEvent || params.Event || '';
            const confSid  = params.ConferenceSid || '';
            const callSid  = params.CallSid || '';
            console.log(`[conf-status] event="${event}" conf="${confSid}" call="${callSid}"`);

            if (activeCall) {
                if (confSid && !activeCall.conferenceSid) {
                    activeCall.conferenceSid = confSid;
                    console.log(`[conf-status] Stored conferenceSid: ${confSid}`);
                }
                // The second call to join is the PSTN leg
                if (callSid && callSid !== activeCall.sdkCallSid && !activeCall.pstnCallSid) {
                    activeCall.pstnCallSid = callSid;
                    console.log(`[conf-status] Stored pstnCallSid: ${callSid}`);
                }
            }

            res.writeHead(200);
            res.end();
            return;
        }

        // ── POST /pstn-status  (PSTN outbound call status events) ──────────
        if (parsedUrl.pathname === '/pstn-status') {
            // Vobiz uses CallUUID, Twilio-compat uses CallSid
            const callUuid = params.CallUUID || params.CallSid || params.call_uuid || '';
            const status   = params.CallStatus || params.call_status || params.Event || '';
            console.log(`[pstn-status] uuid="${callUuid}" status="${status}" all=${JSON.stringify(params)}`);

            if (activeCall && callUuid && (status === 'answered' || status === 'in-progress' || status === 'ANSWER')) {
                if (!activeCall.pstnCallUuid) {
                    activeCall.pstnCallUuid = callUuid;
                    console.log(`[pstn-status] Stored pstnCallUuid: ${callUuid}`);
                }
            }

            if (activeCall && callUuid && (status === 'completed' || status === 'HANGUP') && activeCall.pstnCallUuid === callUuid) {
                console.log('[pstn-status] PSTN call ended, clearing activeCall');
                activeCall = null;
            }

            res.writeHead(200);
            res.end();
            return;
        }

        // ── POST /register-token ───────────────────────────────────────────
        // Flutter emulator fallback: poll for inbound calls that are waiting
        // in a Vobiz conference room.
        if (req.method === 'GET' && parsedUrl.pathname === '/pending-call') {
            if (activeCall && activeCall.pendingInbound) {
                sendJson(res, 200, {
                    pending:    true,
                    caller:     activeCall.pstnNumber || 'Unknown',
                    roomId:     activeCall.roomId || '',
                    joinNumber: callerId,
                });
            } else {
                sendJson(res, 200, { pending: false });
            }
            return;
        }

        if (req.method === 'POST' && parsedUrl.pathname === '/answer-inbound') {
            if (!activeCall || !activeCall.pendingInbound) {
                sendJson(res, 404, { error: 'No pending inbound call' });
                return;
            }
            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /join-conference  (killed-app recovery: join existing conference room) ──
        if (req.method === 'POST' && parsedUrl.pathname === '/join-conference') {
            const roomId = String(params.roomId || params.room_id || '').trim();
            if (!roomId) {
                sendJson(res, 400, { error: 'roomId required' });
                return;
            }

            if (!activeCall || activeCall.roomId !== roomId || !activeCall.pendingInbound) {
                sendJson(res, 404, { 
                    error: 'Conference room not found or no pending inbound call',
                    debug: { roomId, activeCallRoomId: activeCall?.roomId, pendingInbound: activeCall?.pendingInbound }
                });
                return;
            }

            // Room exists and is waiting — return success so app can proceed.
            // Do NOT clear pendingInbound here; it stays true so the /answer webhook
            // still recognises the subsequent SIP INVITE as an inbound conference join.
            console.log(`[join-conference] App recovering from killed state, roomId=${roomId}`);
            sendJson(res, 200, { 
                success: true, 
                roomId: activeCall.roomId,
                joinNumber: callerId 
            });
            return;
        }

        if (req.method === 'POST' && parsedUrl.pathname === '/register-token') {
            const username = String(params.username || params.Username || '').trim();
            const token    = String(params.token    || params.Token    || '').trim();
            if (!username || !token) {
                sendText(res, 400, 'username and token are required');
                return;
            }
            const storedBackendUrl = String(params.backend_url || params.backendUrl || '').trim();
            registeredPushTokens.set(username, { token, backendUrl: storedBackendUrl });
            console.log(`Push token registered for ${username}`);
            sendJson(res, 200, { success: true });
            return;
        }

        // ── POST /decline-inbound ──────────────────────────────────────────
        if (req.method === 'POST' && parsedUrl.pathname === '/decline-inbound') {
            if (!activeCall || !activeCall.pstnCallUuid) {
                sendJson(res, 404, { error: 'No active inbound call' });
                return;
            }
            const uuidToHangup = activeCall.pstnCallUuid;
            activeCall = null;
            if (vobizAccountSid && vobizAuthToken) {
                vobizApi(`/Account/${vobizAccountSid}/Call/${uuidToHangup}/`, null, 'DELETE')
                    .catch(e => console.error('[decline] hangup error:', e.message));
            }
            sendJson(res, 200, { success: true });
            return;
        }

        // ── Hangup events ──────────────────────────────────────────────────
        const eventName =
            params.Event || params.event ||
            params.CallStatus || params.callstatus || '';

        if (
            parsedUrl.pathname === '/hangup' ||
            String(eventName).toLowerCase().includes('hangup')
        ) {
            const hungCallId = params.CallUUID || params.CallSid || params.callSid || params.callId || '';
            if (hungCallId) removeCallFromRoom(hungCallId);

            if (activeCall && (
                activeCall.sdkCallSid  === hungCallId ||
                activeCall.pstnCallUuid === hungCallId
            )) {
                // SDK leg hung up while in conference mode — terminate all remaining PSTN legs
                // so the caller's phone is disconnected and not left in an empty conference room.
                if (activeCall.sdkCallSid === hungCallId && activeCall.roomId) {
                    if (activeCall.pstnCallUuid) {
                        vobizHangupCall(activeCall.pstnCallUuid)
                            .catch(e => console.error('[hangup] PSTN hangup failed:', e.message));
                    }
                    if (activeCall.secondCallUuid) {
                        vobizHangupCall(activeCall.secondCallUuid)
                            .catch(e => console.error('[hangup] second-call hangup failed:', e.message));
                    }
                    if (activeCall.addedCallUuid) {
                        vobizHangupCall(activeCall.addedCallUuid)
                            .catch(e => console.error('[hangup] added-call hangup failed:', e.message));
                    }
                }
                console.log('[hangup] Clearing activeCall');
                activeCall = null;
            }

            console.log(`Hangup event${hungCallId ? ` (${hungCallId})` : ''}`);
            sendXml(res, buildEmptyResponseXml());
            return;
        }

        // ── Answer webhook (/  or  /answer) ───────────────────────────────
        const isAnswerWebhook =
            parsedUrl.pathname === '/' || parsedUrl.pathname === '/answer';

        if (!isAnswerWebhook) {
            sendText(res, 404, 'Not found');
            return;
        }

        // Validate config
        const callerIdError = validateCallerId(callerId);
        if (callerIdError) {
            console.error(callerIdError);
            sendXml(res, buildConfigErrorResponseXml(callerIdError));
            return;
        }

        const rawFrom    = params.From || params.from || '';
        const rawTo      = params.To || params.to || '';
        const routeType  = String(params.RouteType || params.routeType || '').toLowerCase();
        const isSipLeg   = rawFrom.startsWith('sip:') || routeType === 'sip';
        const toIsVobizNumber = callerId && isSameNumber(rawTo, callerId);
        const isInboundConferenceJoin =
            !!(activeCall && activeCall.pendingInbound && isSipLeg && toIsVobizNumber);
        const isSdkCall  = isSipLeg && (!toIsVobizNumber || isInboundConferenceJoin);

        console.log(`[answer-route] From="${rawFrom}" To="${rawTo}" RouteType="${routeType}" isSipLeg=${isSipLeg} toIsVobizNumber=${toIsVobizNumber} pendingJoin=${isInboundConferenceJoin} branch=${isSdkCall ? 'sdk-leg' : 'inbound-pstn'}`);

        // ── Outbound SDK call ──────────────────────────────────────────────
        if (isSdkCall) {
            // Vobiz sends CallUUID (not CallSid like Twilio)
            const sdkCallSid =
                params.CallUUID || params.CallSid || params.callSid || params.callId || params.call_id || '';

            // Check legacy conference merge first
            const legacyRoom = sdkCallSid ? getRoomForCall(sdkCallSid) : null;
            if (legacyRoom) {
                console.log(`[legacy-conference] ${sdkCallSid} -> room ${legacyRoom}`);
                sendXml(res, buildConferenceXml(legacyRoom, callerId));
                return;
            }

            if (isInboundConferenceJoin && activeCall.roomId) {
                activeCall.sdkCallSid = sdkCallSid;
                activeCall.pendingInbound = false;
                console.log(`[inbound-conf] SDK ${sdkCallSid} joined room ${activeCall.roomId}`);
                sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Conference stayAlone="true">${escapeXml(activeCall.roomId)}</Conference>
</Response>`);
                return;
            }

            // Resolve destination
            let destination =
                lastDialedNumber ||
                params.To || params.to ||
                params.Destination || params.destination || '';

            if (String(destination).startsWith('sip:')) {
                const m = String(destination).match(/^sip:(.*?)@/);
                if (m && m[1]) destination = m[1];
            }
            destination = formatToE164(destination);

            if (!destination) {
                if (defaultDestination) {
                    destination = formatToE164(defaultDestination);
                    console.log('Using DEFAULT_DESTINATION:', destination);
                } else {
                    sendText(res, 400, 'No destination. POST /call first or set DEFAULT_DESTINATION.');
                    return;
                }
            }

            if (isSameNumber(destination, callerId)) {
                sendText(res, 400, 'Cannot call your own number');
                return;
            }

            // Store call state so hold/transfer endpoints have the SDK call UUID.
            activeCall = {
                sdkCallSid,
                pstnNumber:   destination,
                pstnCallUuid: null,
            };

            console.log(`[outbound] Dialing ${destination}`);
            sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Dial callerId="${escapeXml(callerId)}">
        <Number>${escapeXml(destination)}</Number>
    </Dial>
</Response>`);
            return;
        }

        // ── Inbound PSTN call ──────────────────────────────────────────────
        const sipEndpointError = validateSipEndpoint(sipEndpoint);
        if (sipEndpointError) {
            console.error(sipEndpointError);
            sendXml(res, buildConfigErrorResponseXml(sipEndpointError));
            return;
        }

        const inboundCallUuid = params.CallUUID || '';
        const normalizedCaller =
            rawFrom && !rawFrom.startsWith('+') && !rawFrom.startsWith('sip:')
                ? `+${rawFrom}`
                : rawFrom || 'Unknown';

        console.log(`Inbound PSTN from ${normalizedCaller} -> ${sipEndpoint}`);

        if (canUseConferenceMode()) {
            const roomId = `vi_${Date.now()}`;
            activeCall = {
                roomId,
                sdkCallSid:     null,
                pstnNumber:     normalizedCaller,
                pstnCallUuid:   inboundCallUuid,
                pendingInbound: true,
            };
            console.log(`[inbound-conf] PSTN waiting in room ${roomId}, caller: ${normalizedCaller}`);
            sendFcmPush(normalizedCaller, null, roomId).catch(e => console.error('[FCM]', e.message));

            sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Speak>Please wait while we connect your call.</Speak>
    <Conference stayAlone="true">${escapeXml(roomId)}</Conference>
</Response>`);
            return;
        }

        activeCall = {
            pstnNumber:   normalizedCaller,
            pstnCallUuid: inboundCallUuid,
        };
        console.log(`[inbound-direct] Routing PSTN ${normalizedCaller} directly to ${sipEndpoint}`);
        sendFcmPush(normalizedCaller, null).catch(e => console.error('[FCM]', e.message));

        sendXml(res, `<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Dial callerId="${escapeXml(callerId)}" timeout="30">
        <User>${escapeXml(sipEndpoint)}</User>
    </Dial>
</Response>`);
    });
});

server.listen(port, () => {
    const confMode = vobizAccountSid && vobizAuthToken && publicUrl
        ? '✓ Conference mode active (hold announcement enabled)'
        : '⚠  Standard mode (add VOBIZ_ACCOUNT_SID, VOBIZ_AUTH_TOKEN, PUBLIC_URL for hold announcement)';

    console.log(`
-------------------------------------------------------
  Vobiz Backend  →  port ${port}
-------------------------------------------------------
  Mode: ${confMode}

  Flutter outbound helper:
     POST http://127.0.0.1:${port}/call

  Vobiz Answer URL (set in Vobiz console):
     https://<your-ngrok-url>/answer

  Hold announcement URL (auto-used when holding):
     https://<your-ngrok-url>/hold-announcement

  Required .env:
     CALLER_ID          = +15550003333
     SIP_ENDPOINT       = sip:username@registrar.vobiz.ai

  Optional (for hold announcement):
     VOBIZ_ACCOUNT_SID  = from Vobiz dashboard → API Keys
     VOBIZ_AUTH_TOKEN   = from Vobiz dashboard → API Keys
     PUBLIC_URL         = https://your-ngrok-url
-------------------------------------------------------
    `);
});
