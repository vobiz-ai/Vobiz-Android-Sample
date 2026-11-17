// Vobiz sample backend for the Flutter app (apps/vobiz_demo) and the browser client (client/).
//
// What it does:
//   * Answer URL for your Vobiz application: an app's outbound call dials the number (or SIP user)
//     it asked for; a call to your Vobiz number rings the app's SIP user. When the app is closed,
//     Vobiz holds that call and wakes the phone with a push (Vobiz push-to-wake), so nothing here
//     sends pushes.
//   * Routes for the app, protected by APP_KEY: access tokens (JWT), the phone's push registration
//     with Vobiz, and blind transfer. They use your Auth Token, which never leaves this server.
//
// Every Vobiz webhook is checked against its X-Vobiz-Signature when VOBIZ_AUTH_TOKEN and
// PUBLIC_URL are set. Run it with `npm start`; settings are in .env (see .env.example).

require('dotenv').config({ quiet: true });
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const querystring = require('querystring');

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

function clampInt(value, fallback, min, max) {
    const n = Number.parseInt(value, 10);
    if (!Number.isFinite(n)) return fallback;
    return Math.min(max, Math.max(min, n));
}

function loadConfig(env = process.env) {
    const trim = (v) => String(v || '').trim();
    return {
        port: clampInt(env.PORT, 3000, 1, 65535),
        publicUrl: trim(env.PUBLIC_URL).replace(/\/+$/, ''),
        // VOBIZ_ACCOUNT_SID is the old name of VOBIZ_AUTH_ID and still works.
        authId: trim(env.VOBIZ_AUTH_ID || env.VOBIZ_ACCOUNT_SID),
        authToken: trim(env.VOBIZ_AUTH_TOKEN),
        callerId: trim(env.CALLER_ID),
        // Who a call to your Vobiz number rings: one or more SIP URIs, comma separated.
        sipEndpoints: trim(env.SIP_ENDPOINT).split(',').map((s) => s.trim()).filter(Boolean),
        defaultDestination: trim(env.DEFAULT_DESTINATION),
        defaultCountryCode: trim(env.DEFAULT_COUNTRY_CODE) || '91',
        ringSeconds: clampInt(env.RING_SECONDS, 45, 10, 120),
        appKey: trim(env.APP_KEY),
        jwtAppId: trim(env.JWT_APP_ID),
        jwtTtlSeconds: clampInt(env.JWT_TTL_SECONDS, 3600, 180, 86400),
        // Optional allow-list of access-token identities, comma separated.
        tokenIdentities: trim(env.TOKEN_IDENTITIES).split(',').map((s) => s.trim()).filter(Boolean),
        allowUnsignedWebhooks: trim(env.ALLOW_UNSIGNED_WEBHOOKS).toLowerCase() === 'true',
        vobizApiBase: trim(env.VOBIZ_API_BASE) || 'https://api.vobiz.ai',
    };
}

const REGISTRAR = 'registrar.vobiz.ai';
const SUB_RE = /^[A-Za-z0-9_-]{1,50}$/;
const SIP_USER_RE = /^[A-Za-z0-9_.+-]{1,120}$/;
const E164_RE = /^\+\d{7,15}$/;
const CALL_UUID_RE = /^[A-Za-z0-9-]{8,64}$/;

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function escapeXml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

function xml(body) {
    return `<?xml version="1.0" encoding="UTF-8"?>\n<Response>${body}</Response>`;
}

function speakXml(message) {
    return xml(`\n    <Speak>${escapeXml(message)}</Speak>\n`);
}

function normalizePhoneNumber(value) {
    return String(value || '').replace(/[^\d+]/g, '').trim();
}

function formatToE164(value, countryCode) {
    const n = normalizePhoneNumber(value);
    if (!n) return '';
    if (n.startsWith('+')) return n;
    if (n.length === 10) return `+${countryCode}${n}`;
    if (n.length === 11 && n.startsWith('0')) return `+${countryCode}${n.substring(1)}`;
    return `+${n}`;
}

function isSameNumber(a, b) {
    const left = normalizePhoneNumber(a).replace(/^\+/, '');
    const right = normalizePhoneNumber(b).replace(/^\+/, '');
    return left.length > 0 && left === right;
}

function hasPlaceholder(value) {
    return /<[^>]+>/.test(String(value || ''));
}

function mask(value) {
    const text = String(value || '');
    if (text.length <= 8) return '****';
    return `${text.slice(0, 4)}…${text.slice(-4)}`;
}

function redact(params) {
    const out = {};
    for (const [key, value] of Object.entries(params || {})) {
        out[key] = /(password|pass|token|secret|key)/i.test(key) ? mask(value) : value;
    }
    return out;
}

function sha256(text) {
    return crypto.createHash('sha256').update(String(text)).digest();
}

/** Constant-time string comparison. */
function safeEqual(a, b) {
    return crypto.timingSafeEqual(sha256(a), sha256(b));
}

function sendXml(res, body) {
    res.writeHead(200, { 'Content-Type': 'text/xml' });
    res.end(body);
}

function sendJson(res, status, obj) {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(obj));
}

function parseBody(req, raw) {
    const type = String(req.headers['content-type'] || '').toLowerCase();
    if (!raw.trim()) return {};
    if (type.includes('application/json')) return JSON.parse(raw);
    return querystring.parse(raw);
}

/** The value of the first parameter whose name ends with [suffix] (any case). */
function paramEndingWith(params, suffix) {
    const want = suffix.toLowerCase();
    for (const [key, value] of Object.entries(params)) {
        if (key.toLowerCase().endsWith(want) && String(value || '').trim()) return String(value).trim();
    }
    return '';
}

/** A SIP endpoint's username, from "alice", "sip:alice" or "sip:alice@registrar.vobiz.ai". */
function sipUsername(value) {
    return String(value || '').trim().replace(/^sip:/i, '').split('@')[0];
}

// ---------------------------------------------------------------------------
// The server
// ---------------------------------------------------------------------------

function createServer(config = loadConfig(), deps = {}) {
    const log = deps.log || ((...args) => console.log(new Date().toISOString(), ...args));
    const fetchFn = deps.fetch || globalThis.fetch;
    const verifySignatures = Boolean(config.authToken && config.publicUrl && !config.allowUnsignedWebhooks);
    const seenNonces = new Map();

    // ── Live calls, for transfer ─────────────────────────────────────────────
    // The Transfer API wants the call's A-leg CallUUID and the side to move. The A-leg is the
    // CallUUID in this server's /answer webhook: the caller's call when someone rings your number
    // (the app is its B-leg), the app's own call when the app dials out. The CallUUID the app sees
    // on a call to it comes from Vobiz's WebRTC gateway, which the Call API does not know.
    const liveCalls = new Map(); // SIP user -> { aLeg, appIsALeg, at }
    function rememberCall(user, aLeg, appIsALeg) {
        if (!user || !aLeg) return;
        const now = Date.now();
        for (const [u, c] of liveCalls) if (now - c.at > 4 * 60 * 60 * 1000) liveCalls.delete(u);
        liveCalls.set(user, { aLeg, appIsALeg, at: now });
    }
    function forgetCall(aLeg) {
        for (const [u, c] of liveCalls) if (c.aLeg === aLeg) liveCalls.delete(u);
    }

    // ── Vobiz REST API (JSON, X-Auth-ID / X-Auth-Token) ──────────────────────
    async function vobizRequest(method, pathname, body) {
        if (!config.authId || !config.authToken) {
            const error = new Error('Set VOBIZ_AUTH_ID and VOBIZ_AUTH_TOKEN in the server\'s .env');
            error.httpStatus = 503;
            throw error;
        }
        const response = await fetchFn(`${config.vobizApiBase}${pathname}`, {
            method,
            headers: {
                'X-Auth-ID': config.authId,
                'X-Auth-Token': config.authToken,
                'Content-Type': 'application/json',
                Accept: 'application/json',
            },
            body: body ? JSON.stringify(body) : undefined,
            signal: AbortSignal.timeout(15000),
        });
        const text = await response.text();
        let json = null;
        try { json = text ? JSON.parse(text) : null; } catch { /* not JSON */ }
        log(`[vobiz-api] ${method} ${pathname} -> ${response.status}`);
        if (!response.ok) {
            const reason = (json && (json.message || json.error || json.detail)) || text.slice(0, 200);
            const error = new Error(`Vobiz answered ${response.status}${reason ? `: ${reason}` : ''}`);
            error.httpStatus = 502;
            throw error;
        }
        return json;
    }
    const accountPath = (rest) => `/api/v1/Account/${encodeURIComponent(config.authId)}${rest}`;

    // ── Vobiz webhook signatures ─────────────────────────────────────────────
    // Vobiz signs base64(HMAC-SHA256(authToken, url + "." + nonce)) (V3) or url + nonce (V2), where
    // url is the URL it called without the query string. A nonce is accepted once.
    function checkSignature(req, pathname) {
        const baseUrl = `${config.publicUrl}${pathname}`;
        const checks = [
            ['x-vobiz-signature-v3', 'x-vobiz-signature-v3-nonce', '.'],
            ['x-vobiz-signature-ma-v3', 'x-vobiz-signature-v3-nonce', '.'],
            ['x-vobiz-signature-v2', 'x-vobiz-signature-v2-nonce', ''],
            ['x-vobiz-signature-ma-v2', 'x-vobiz-signature-v2-nonce', ''],
        ];
        let sawSignature = false;
        for (const [sigHeader, nonceHeader, separator] of checks) {
            const signature = String(req.headers[sigHeader] || '');
            const nonce = String(req.headers[nonceHeader] || '');
            if (!signature || !nonce) continue;
            sawSignature = true;
            const expected = crypto.createHmac('sha256', config.authToken)
                .update(baseUrl + separator + nonce).digest('base64');
            // A header may carry several comma-separated signatures.
            if (!signature.split(',').some((s) => safeEqual(s.trim(), expected))) continue;
            const now = Date.now();
            for (const [n, at] of seenNonces) if (now - at > 15 * 60 * 1000) seenNonces.delete(n);
            if (seenNonces.has(nonce)) return 'nonce already used (a replayed request)';
            seenNonces.set(nonce, now);
            return 'ok';
        }
        return sawSignature
            ? `signature does not match ${baseUrl} (is PUBLIC_URL exactly the address Vobiz calls?)`
            : 'no X-Vobiz-Signature header';
    }

    // ── The app's key (X-App-Key) ────────────────────────────────────────────
    function appKeyProblem(req) {
        if (!config.appKey) return [503, 'Set APP_KEY in the server\'s .env, and build the app with the same VOBIZ_APP_KEY'];
        const sent = String(req.headers['x-app-key'] || '');
        if (!sent || !safeEqual(sent, config.appKey)) return [401, 'Send this server\'s app key in X-App-Key'];
        return null;
    }

    // ── Answer URL ───────────────────────────────────────────────────────────
    function onAnswer(params) {
        const from = String(params.From || params.from || '');
        const to = String(params.To || params.to || '');
        const routeType = String(params.RouteType || params.routeType || '').toLowerCase();
        const fromApp = from.toLowerCase().startsWith('sip:') || routeType === 'sip';
        log(`[answer] ${fromApp ? 'call from the app' : 'call to your number'} CallUUID=${params.CallUUID || '?'}`);

        if (!config.callerId || hasPlaceholder(config.callerId)) {
            return speakXml('This server is not set up yet: CALLER_ID is missing in its settings.');
        }

        if (fromApp) {
            // The SDK's dialUser option (X-VH-DialUser): ring another app or SIP phone.
            const dialUser = sipUsername(paramEndingWith(params, 'dialuser'));
            if (dialUser) {
                if (!SIP_USER_RE.test(dialUser)) return speakXml('That SIP user name is not valid.');
                log(`[answer] dialling SIP user ${dialUser}`);
                rememberCall(sipUsername(from), params.CallUUID, true);
                return xml(`
    <Dial callerId="${escapeXml(config.callerId)}" timeout="${config.ringSeconds}">
        <User>${escapeXml(`sip:${dialUser}@${REGISTRAR}`)}</User>
    </Dial>
`);
            }
            let destination = to;
            if (destination.toLowerCase().startsWith('sip:')) destination = sipUsername(destination);
            destination = formatToE164(destination, config.defaultCountryCode)
                || formatToE164(config.defaultDestination, config.defaultCountryCode);
            if (!E164_RE.test(destination)) return speakXml('There is no valid number to call.');
            if (isSameNumber(destination, config.callerId)) return speakXml('You cannot call your own Vobiz number.');
            log(`[answer] dialling ${mask(destination)}`);
            rememberCall(sipUsername(from), params.CallUUID, true);
            return xml(`
    <Dial callerId="${escapeXml(config.callerId)}" timeout="60">
        <Number>${escapeXml(destination)}</Number>
    </Dial>
`);
        }

        // A call to your Vobiz number: ring the app. A closed app is woken by Vobiz push.
        const endpoints = config.sipEndpoints.filter((e) => /^sip:[^@\s]+@[^@\s]+$/i.test(e) && !hasPlaceholder(e));
        if (endpoints.length === 0) {
            return speakXml('This server is not set up yet: SIP_ENDPOINT is missing in its settings.');
        }
        log(`[answer] ringing ${endpoints.map(sipUsername).join(', ')}`);
        for (const e of endpoints) rememberCall(sipUsername(e), params.CallUUID, false);
        return xml(`
    <Dial timeout="${config.ringSeconds}">
${endpoints.map((e) => `        <User>${escapeXml(e)}</User>`).join('\n')}
    </Dial>
`);
    }

    // ── POST /token: an access token (JWT) for the app ──────────────────────
    async function onToken(req, res, url, body) {
        const sub = String(body.sub || url.searchParams.get('sub') || '').trim();
        if (!SUB_RE.test(sub)) return sendJson(res, 400, { error: 'sub must be 1 to 50 letters, digits, _ or -' });
        if (config.tokenIdentities.length && !config.tokenIdentities.includes(sub)) {
            return sendJson(res, 403, { error: `${sub} is not in TOKEN_IDENTITIES` });
        }
        if (!config.jwtAppId) {
            // Without an app the registrar refuses the token (10001) on accounts without a default app.
            return sendJson(res, 503, { error: 'Set JWT_APP_ID to the Vobiz application whose Answer URL handles this app\'s calls' });
        }
        // nbf a minute back: a registrar clock a second behind this one would refuse "not valid yet" (10005).
        const nbf = Math.floor(Date.now() / 1000) - 60;
        const claims = {
            iss: config.authId,
            sub,
            nbf,
            exp: nbf + config.jwtTtlSeconds,
            app: config.jwtAppId,
            per: { voice: { incoming_allow: true, outgoing_allow: true } },
        };
        const minted = await vobizRequest('POST', accountPath('/JWT/Token/'), claims);
        if (!minted || typeof minted.token !== 'string' || !minted.token) {
            return sendJson(res, 502, { error: 'Vobiz returned no token' });
        }
        const reason = typeof body.reason === 'string' ? body.reason.slice(0, 20) : '';
        log(`[token] ${sub}_${mask(config.authId)} until ${new Date(claims.exp * 1000).toISOString()}${reason ? ` (${reason})` : ''}`);
        sendJson(res, 200, { token: minted.token, sub, exp: claims.exp, sip_username: `${sub}_${config.authId}` });
    }

    // ── POST /push/devices/register, DELETE /push/devices/logout ─────────────
    // The SDK's VobizPushDevices, pointed at this server, sends the same body Vobiz expects; this
    // adds the account's credentials so they never ship in the app.
    async function onPushRegister(req, res, url, body) {
        const fields = ['device_id', 'push_token', 'platform', 'push_type', 'app_bundle_id', 'app_version', 'sdk_version', 'sip_username'];
        const device = {};
        for (const field of fields) device[field] = String(body[field] || '').trim().slice(0, field === 'push_token' ? 4096 : 200);
        for (const field of ['device_id', 'push_token', 'app_bundle_id', 'sip_username']) {
            if (!device[field]) return sendJson(res, 400, { error: `${field} is required` });
        }
        if (!['android', 'ios'].includes(device.platform)) device.platform = 'android';
        if (!device.push_type) device.push_type = 'voip';
        await vobizRequest('POST', '/api/v1/devices/register', device);
        log(`[push] device ${mask(device.device_id)} registered for ${device.sip_username} (${device.app_bundle_id})`);
        sendJson(res, 200, { ok: true });
    }

    async function onPushLogout(req, res, url, body) {
        const deviceId = String(body.device_id || '').trim().slice(0, 200);
        if (!deviceId) return sendJson(res, 400, { error: 'device_id is required' });
        await vobizRequest('DELETE', '/api/v1/devices/logout', { device_id: deviceId });
        log(`[push] device ${mask(deviceId)} removed`);
        sendJson(res, 200, { ok: true });
    }

    // ── POST /calls/transfer: send the other party to a number or SIP user ──
    // Body: { sip_username: the app's SIP user (VobizClient.sipUsername), to, call_uuid?: optional }.
    async function onTransfer(req, res, url, body) {
        const user = sipUsername(body.sip_username);
        const callUuid = String(body.call_uuid || '').trim();
        if (!SIP_USER_RE.test(user) && !CALL_UUID_RE.test(callUuid)) {
            return sendJson(res, 400, { error: 'sip_username (the app\'s SIP user) is required' });
        }
        const target = transferTarget(body.to);
        if (!target) return sendJson(res, 400, { error: 'to must be an E.164 number such as +919876543210, or a SIP user name' });
        if (!config.publicUrl) return sendJson(res, 503, { error: 'Set PUBLIC_URL: Vobiz fetches the transfer XML from it' });
        const call = liveCalls.get(user) || [...liveCalls.values()].find((c) => c.aLeg === callUuid);
        if (!call) {
            return sendJson(res, 409, { error: 'This server answered no live call for this phone. Transfer works for calls that went through its /answer' });
        }
        // Move the other party: the caller's A-leg when the app was rung, the B-leg when the app dialled.
        const legs = call.appIsALeg ? 'bleg' : 'aleg';
        await vobizRequest('POST', accountPath(`/Call/${encodeURIComponent(call.aLeg)}/`), {
            legs,
            [`${legs}_url`]: `${config.publicUrl}/transfer-bridge?to=${encodeURIComponent(target)}`,
            [`${legs}_method`]: 'POST',
        });
        log(`[transfer] ${legs} of ${call.aLeg} -> ${target.startsWith('sip:') ? target : mask(target)}`);
        sendJson(res, 200, { message: 'Transfer started' });
    }

    function transferTarget(value) {
        const raw = String(value || '').trim();
        if (!raw) return '';
        if (/^\+?[\d\s()-]+$/.test(raw)) {
            const number = formatToE164(raw, config.defaultCountryCode);
            return E164_RE.test(number) ? number : '';
        }
        const user = sipUsername(raw);
        return SIP_USER_RE.test(user) ? `sip:${user}@${REGISTRAR}` : '';
    }

    function onTransferBridge(url) {
        const target = transferTarget(url.searchParams.get('to'));
        if (!target) return speakXml('The transfer destination is not valid. Goodbye.');
        const dialTarget = target.startsWith('sip:')
            ? `<User>${escapeXml(target)}</User>`
            : `<Number>${escapeXml(target)}</Number>`;
        return xml(`
    <Speak>Please hold while we transfer your call.</Speak>
    <Dial callerId="${escapeXml(config.callerId)}" timeout="60">${dialTarget}</Dial>
    <Speak>We could not reach the transfer destination. Goodbye.</Speak>
`);
    }

    // ── Routing ──────────────────────────────────────────────────────────────
    const webhookRoutes = new Set(['/', '/answer', '/hangup', '/transfer-bridge']);
    const appRoutes = {
        'POST /token': onToken,
        'POST /push/devices/register': onPushRegister,
        'DELETE /push/devices/logout': onPushLogout,
        'POST /calls/transfer': onTransfer,
    };

    function serveClientFile(req, res) {
        // Only the web client in client/: the path is resolved and must stay inside it, so a request
        // such as /client/../.env can never read this server's own files.
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
            res.writeHead(200, { 'Content-Type': contentType });
            res.end(data);
        });
    }

    const server = http.createServer((req, res) => {
        if (req.url.startsWith('/client')) return serveClientFile(req, res);

        let raw = '';
        req.on('data', (chunk) => {
            raw += chunk;
            if (raw.length > 64 * 1024) req.destroy();
        });
        req.on('end', async () => {
            const url = new URL(req.url, 'http://localhost');
            log(`${req.method} ${url.pathname}`);
            try {
                if (req.method === 'GET' && url.pathname === '/health') {
                    return sendJson(res, 200, {
                        ok: true,
                        signedWebhooks: verifySignatures,
                        appRoutes: Boolean(config.appKey),
                        accessTokens: Boolean(config.appKey && config.authId && config.authToken && config.jwtAppId),
                    });
                }

                const appRoute = appRoutes[`${req.method} ${url.pathname}`];
                if (appRoute) {
                    const problem = appKeyProblem(req);
                    if (problem) return sendJson(res, problem[0], { error: problem[1] });
                    let body;
                    try { body = raw.trim() ? JSON.parse(raw) : {}; } catch { return sendJson(res, 400, { error: 'Send a JSON body' }); }
                    return await appRoute(req, res, url, body && typeof body === 'object' ? body : {});
                }

                if (!webhookRoutes.has(url.pathname) || !['GET', 'POST'].includes(req.method)) {
                    return sendJson(res, 404, { error: 'Not found' });
                }
                if (verifySignatures) {
                    const verdict = checkSignature(req, url.pathname);
                    if (verdict !== 'ok') {
                        log(`[webhook] refused ${url.pathname}: ${verdict}. (ALLOW_UNSIGNED_WEBHOOKS=true turns the check off for local experiments.)`);
                        res.writeHead(403); res.end('Invalid signature'); return;
                    }
                }
                let params;
                try {
                    params = { ...Object.fromEntries(url.searchParams), ...parseBody(req, raw) };
                } catch {
                    res.writeHead(400); res.end('Bad request'); return;
                }
                log('[params]', JSON.stringify(redact(params)));
                if (url.pathname === '/hangup') {
                    log(`[hangup] CallUUID=${params.CallUUID || '?'} cause=${params.HangupCause || params.HangupCauseName || '?'}`);
                    if (params.CallUUID) forgetCall(String(params.CallUUID));
                    return sendXml(res, xml(''));
                }
                if (url.pathname === '/transfer-bridge') return sendXml(res, onTransferBridge(url));
                return sendXml(res, onAnswer(params));
            } catch (error) {
                log(`[error] ${req.method} ${url.pathname}: ${error.message}`);
                // A timeout or network failure reaching Vobiz is a 502 too.
                const status = error.httpStatus || (error.name === 'TimeoutError' || error.cause ? 502 : 500);
                if (!res.headersSent) sendJson(res, status, { error: error.message });
            }
        });
    });
    server.verifySignatures = verifySignatures;
    return server;
}

module.exports = { createServer, loadConfig, formatToE164 };

if (require.main === module) {
    const config = loadConfig();
    const server = createServer(config);
    server.listen(config.port, () => {
        const yes = (v) => (v ? 'yes' : 'no');
        console.log(`
-------------------------------------------------------------
  Vobiz sample backend on port ${config.port}
-------------------------------------------------------------
  Answer URL:  ${config.publicUrl || 'https://<your-public-url>'}/answer
  Hangup URL:  ${config.publicUrl || 'https://<your-public-url>'}/hangup

  CALLER_ID set:              ${yes(config.callerId && !hasPlaceholder(config.callerId))}
  SIP_ENDPOINT (inbound):     ${config.sipEndpoints.map(sipUsername).join(', ') || 'not set'}
  Vobiz credentials set:      ${yes(config.authId && config.authToken)}
  Webhook signatures checked: ${yes(server.verifySignatures)}${server.verifySignatures ? '' : '  <- set VOBIZ_AUTH_TOKEN and PUBLIC_URL'}
  App routes (APP_KEY):       ${yes(config.appKey)}
  Access tokens (JWT_APP_ID): ${yes(config.appKey && config.jwtAppId && config.authId && config.authToken)}
-------------------------------------------------------------`);
    });
}
