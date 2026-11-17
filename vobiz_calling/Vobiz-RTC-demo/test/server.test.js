// Tests for server.js: no network, no .env. Vobiz's API is a fake `fetch`.
//   npm test
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { test } = require('node:test');
const { createServer, loadConfig } = require('../server');

const PUBLIC_URL = 'https://sample.example.com';
const AUTH_ID = 'MA_TEST0001';
const AUTH_TOKEN = 'test-auth-token-not-real';
const APP_KEY = 'test-app-key-not-real';

const BASE_ENV = {
    PUBLIC_URL,
    VOBIZ_AUTH_ID: AUTH_ID,
    VOBIZ_AUTH_TOKEN: AUTH_TOKEN,
    CALLER_ID: '+918000000000',
    SIP_ENDPOINT: 'sip:alice@registrar.vobiz.ai',
    APP_KEY,
    JWT_APP_ID: '12345678',
};

/** Starts a server with [env] and a fake Vobiz API; returns helpers. */
async function start(env = {}, vobiz = () => ({ status: 200, body: {} })) {
    const calls = [];
    const fakeFetch = async (url, init) => {
        const body = init.body ? JSON.parse(init.body) : undefined;
        calls.push({ url, method: init.method, headers: init.headers, body });
        const reply = vobiz({ url, method: init.method, body });
        return new Response(JSON.stringify(reply.body ?? {}), { status: reply.status ?? 200 });
    };
    const server = createServer(loadConfig({ ...BASE_ENV, ...env }), { fetch: fakeFetch, log: () => {} });
    await new Promise((resolve) => server.listen(0, resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    return {
        calls,
        base,
        close: () => new Promise((resolve) => server.close(resolve)),
        request: (path, init = {}) => fetch(`${base}${path}`, init),
        app: (method, path, body, key = APP_KEY) => fetch(`${base}${path}`, {
            method,
            headers: { 'Content-Type': 'application/json', ...(key ? { 'X-App-Key': key } : {}) },
            body: body === undefined ? undefined : JSON.stringify(body),
        }),
    };
}

/** A webhook as Vobiz sends it: form-encoded, signed V3 over PUBLIC_URL + path + "." + nonce. */
function webhook(s, path, params, { nonce = crypto.randomUUID(), token = AUTH_TOKEN, signedPath } = {}) {
    const urlPath = (signedPath ?? path).split('?')[0];
    const signature = crypto.createHmac('sha256', token).update(`${PUBLIC_URL}${urlPath}.${nonce}`).digest('base64');
    return s.request(path, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-Vobiz-Signature-V3': signature,
            'X-Vobiz-Signature-V3-Nonce': nonce,
        },
        body: new URLSearchParams(params).toString(),
    });
}

test('health reports what is configured, without secrets', async () => {
    const s = await start();
    try {
        const res = await s.request('/health');
        assert.equal(res.status, 200);
        const body = await res.json();
        assert.deepEqual(body, { ok: true, signedWebhooks: true, appRoutes: true, accessTokens: true });
        assert.ok(!JSON.stringify(body).includes(AUTH_TOKEN));
    } finally { await s.close(); }
});

test('static files: only the web client', async () => {
    const s = await start();
    try {
        assert.equal((await s.request('/client/index.html')).status, 200);
        assert.equal((await s.request('/client/app.js?v=2')).status, 200);
        for (const path of ['/client/../server.js', '/client/%2e%2e/server.js', '/client/..%2fserver.js', '/client/../.env', '/client/']) {
            assert.equal((await s.request(path)).status, 404, path);
        }
        assert.equal((await s.request('/client/%E0%A4%A')).status, 400);
    } finally { await s.close(); }
});

test('webhooks need a valid Vobiz signature, used once', async () => {
    const s = await start();
    try {
        const unsigned = await s.request('/answer', { method: 'POST', body: 'From=919876543210&To=918000000000' });
        assert.equal(unsigned.status, 403);
        const wrongToken = await webhook(s, '/answer', { From: '919876543210' }, { token: 'another-token' });
        assert.equal(wrongToken.status, 403);
        const wrongUrl = await webhook(s, '/answer', { From: '919876543210' }, { signedPath: '/elsewhere' });
        assert.equal(wrongUrl.status, 403);
        const nonce = crypto.randomUUID();
        assert.equal((await webhook(s, '/answer', { From: '919876543210' }, { nonce })).status, 200);
        assert.equal((await webhook(s, '/answer', { From: '919876543210' }, { nonce })).status, 403, 'replayed nonce');
    } finally { await s.close(); }
});

test('ALLOW_UNSIGNED_WEBHOOKS turns the check off', async () => {
    const s = await start({ ALLOW_UNSIGNED_WEBHOOKS: 'true' });
    try {
        const res = await s.request('/answer', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'From=919876543210' });
        assert.equal(res.status, 200);
    } finally { await s.close(); }
});

test('a call from the app dials the number with your caller ID', async () => {
    const s = await start();
    try {
        const res = await webhook(s, '/answer', { From: 'sip:alice@registrar.vobiz.ai', To: '919876543210', CallUUID: 'abc-123' });
        const body = await res.text();
        assert.match(body, /<Dial callerId="\+918000000000" timeout="60">\s*<Number>\+919876543210<\/Number>/);
        const tenDigits = await (await webhook(s, '/answer', { From: 'sip:alice@registrar.vobiz.ai', To: '9876543210' })).text();
        assert.match(tenDigits, /<Number>\+919876543210<\/Number>/);
    } finally { await s.close(); }
});

test('dialUser (X-VH-DialUser) rings a SIP user instead', async () => {
    const s = await start();
    try {
        const body = await (await webhook(s, '/answer', { From: 'sip:alice@registrar.vobiz.ai', To: '919876543210', 'X-VH-DialUser': 'bob' })).text();
        assert.match(body, /<User>sip:bob@registrar\.vobiz\.ai<\/User>/);
        const bad = await (await webhook(s, '/answer', { From: 'sip:alice@registrar.vobiz.ai', To: '919876543210', 'X-VH-DialUser': 'bob"><Hangup/>' })).text();
        assert.match(bad, /<Speak>That SIP user name is not valid.<\/Speak>/);
    } finally { await s.close(); }
});

test('the app cannot call your own number or nothing', async () => {
    const s = await start();
    try {
        assert.match(await (await webhook(s, '/answer', { From: 'sip:alice@registrar.vobiz.ai', To: '+918000000000' })).text(), /own Vobiz number/);
        assert.match(await (await webhook(s, '/answer', { From: 'sip:alice@registrar.vobiz.ai', To: 'sip:abc@registrar.vobiz.ai' })).text(), /no valid number/);
    } finally { await s.close(); }
});

test('a call to your number rings every SIP_ENDPOINT in one Dial, caller passed through', async () => {
    const s = await start({ SIP_ENDPOINT: 'sip:alice@registrar.vobiz.ai, sip:bob_MA_TEST0001@registrar.vobiz.ai' });
    try {
        const body = await (await webhook(s, '/answer', { From: '919876543210', To: '918000000000', CallUUID: 'in-1' })).text();
        assert.match(body, /<Dial timeout="45">/);
        assert.ok(!body.includes('callerId'), 'no callerId: the caller\'s number reaches the app');
        assert.match(body, /<User>sip:alice@registrar\.vobiz\.ai<\/User>\s*<User>sip:bob_MA_TEST0001@registrar\.vobiz\.ai<\/User>/);
    } finally { await s.close(); }
});

test('missing settings are spoken, not a broken call', async () => {
    const s = await start({ CALLER_ID: '', SIP_ENDPOINT: '' });
    try {
        assert.match(await (await webhook(s, '/answer', { From: '919876543210' })).text(), /CALLER_ID is missing/);
    } finally { await s.close(); }
    const t = await start({ SIP_ENDPOINT: 'sip:<your-endpoint-username>@registrar.vobiz.ai' });
    try {
        assert.match(await (await webhook(t, '/answer', { From: '919876543210' })).text(), /SIP_ENDPOINT is missing/);
    } finally { await t.close(); }
});

test('hangup answers an empty Response', async () => {
    const s = await start();
    try {
        const res = await webhook(s, '/hangup', { CallUUID: 'abc', HangupCause: 'NORMAL_CLEARING' });
        assert.equal(res.status, 200);
        assert.match(await res.text(), /<Response><\/Response>/);
    } finally { await s.close(); }
});

test('app routes need APP_KEY set and sent', async () => {
    const off = await start({ APP_KEY: '' });
    try {
        assert.equal((await off.app('POST', '/token?sub=alice', {})).status, 503);
    } finally { await off.close(); }
    const s = await start();
    try {
        assert.equal((await s.app('POST', '/token?sub=alice', {}, null)).status, 401);
        assert.equal((await s.app('POST', '/token?sub=alice', {}, 'wrong-key')).status, 401);
        assert.equal(s.calls.length, 0, 'nothing reached Vobiz');
    } finally { await s.close(); }
});

test('/token mints with the app claim and nbf a minute back', async () => {
    const s = await start({}, ({ url }) => (url.includes('/JWT/Token/') ? { body: { api_id: 'x', token: 'eyJ.fake.jwt' } } : { status: 404 }));
    try {
        const before = Math.floor(Date.now() / 1000);
        const res = await s.app('POST', '/token?sub=alice', { reason: 'sign_in' });
        assert.equal(res.status, 200);
        assert.deepEqual(await res.json(), { token: 'eyJ.fake.jwt', sub: 'alice', exp: s.calls[0].body.exp, sip_username: `alice_${AUTH_ID}` });
        const call = s.calls[0];
        assert.equal(call.url, `https://api.vobiz.ai/api/v1/Account/${AUTH_ID}/JWT/Token/`);
        assert.equal(call.headers['X-Auth-ID'], AUTH_ID);
        assert.equal(call.headers['X-Auth-Token'], AUTH_TOKEN);
        assert.equal(call.body.app, '12345678');
        assert.equal(call.body.sub, 'alice');
        assert.ok(call.body.nbf <= before - 59 && call.body.nbf >= before - 61);
        assert.equal(call.body.exp - call.body.nbf, 3600);
        assert.deepEqual(call.body.per, { voice: { incoming_allow: true, outgoing_allow: true } });
    } finally { await s.close(); }
});

test('/token refuses bad identities, identities not allowed, and no JWT_APP_ID', async () => {
    const s = await start({ TOKEN_IDENTITIES: 'alice,bob' }, () => ({ body: { token: 'eyJ.fake.jwt' } }));
    try {
        assert.equal((await s.app('POST', '/token?sub=al%20ice', {})).status, 400);
        assert.equal((await s.app('POST', '/token', {})).status, 400);
        assert.equal((await s.app('POST', '/token?sub=mallory', {})).status, 403);
        assert.equal((await s.app('POST', '/token?sub=bob', {})).status, 200);
    } finally { await s.close(); }
    const t = await start({ JWT_APP_ID: '' });
    try {
        assert.equal((await t.app('POST', '/token?sub=alice', {})).status, 503);
    } finally { await t.close(); }
});

test('push registration goes to Vobiz with the account key, not from the app', async () => {
    const s = await start();
    try {
        const device = {
            device_id: 'install-1', push_token: 'fcm-token-'.padEnd(40, 'x'), platform: 'android', push_type: 'voip',
            app_bundle_id: 'com.example.vobiz_mobile', app_version: '2.0.0', sdk_version: '0.2.0', sip_username: 'alice',
        };
        const res = await s.app('POST', '/push/devices/register', device);
        assert.equal(res.status, 200);
        assert.equal(s.calls[0].url, 'https://api.vobiz.ai/api/v1/devices/register');
        assert.equal(s.calls[0].method, 'POST');
        assert.deepEqual(s.calls[0].body, device);
        assert.equal(s.calls[0].headers['X-Auth-Token'], AUTH_TOKEN);

        assert.equal((await s.app('POST', '/push/devices/register', { ...device, sip_username: '' })).status, 400);

        const out = await s.app('DELETE', '/push/devices/logout', { device_id: 'install-1' });
        assert.equal(out.status, 200);
        assert.equal(s.calls.at(-1).url, 'https://api.vobiz.ai/api/v1/devices/logout');
        assert.equal(s.calls.at(-1).method, 'DELETE');
        assert.deepEqual(s.calls.at(-1).body, { device_id: 'install-1' });
    } finally { await s.close(); }
});

test('a refusal from Vobiz comes back as 502 with its reason', async () => {
    const s = await start({}, () => ({ status: 400, body: { message: 'push_token is invalid' } }));
    try {
        const res = await s.app('POST', '/push/devices/register', { device_id: 'a', push_token: 'b', app_bundle_id: 'c', sip_username: 'd' });
        assert.equal(res.status, 502);
        assert.match((await res.json()).error, /Vobiz answered 400: push_token is invalid/);
    } finally { await s.close(); }
});

test('transfer moves the other party (bleg) to the transfer XML', async () => {
    const s = await start();
    try {
        const res = await s.app('POST', '/calls/transfer', { call_uuid: '1f2e3d4c-aaaa-bbbb-cccc-1234567890ab', to: '9876543211' });
        assert.equal(res.status, 200);
        const call = s.calls[0];
        assert.equal(call.url, `https://api.vobiz.ai/api/v1/Account/${AUTH_ID}/Call/1f2e3d4c-aaaa-bbbb-cccc-1234567890ab/`);
        assert.deepEqual(call.body, {
            legs: 'bleg',
            bleg_url: `${PUBLIC_URL}/transfer-bridge?to=%2B919876543211`,
            bleg_method: 'POST',
        });
        assert.equal((await s.app('POST', '/calls/transfer', { call_uuid: 'x', to: '+919876543211' })).status, 400);
        assert.equal((await s.app('POST', '/calls/transfer', { call_uuid: '1f2e3d4c-aaaa', to: 'not a number!' })).status, 400);
    } finally { await s.close(); }
});

test('the transfer XML dials the number or SIP user it was given', async () => {
    const s = await start();
    try {
        const number = await (await webhook(s, '/transfer-bridge?to=%2B919876543211', {})).text();
        assert.match(number, /<Dial callerId="\+918000000000" timeout="60"><Number>\+919876543211<\/Number><\/Dial>/);
        const user = await (await webhook(s, '/transfer-bridge?to=bob', {})).text();
        assert.match(user, /<User>sip:bob@registrar\.vobiz\.ai<\/User>/);
        const bad = await (await webhook(s, '/transfer-bridge?to=%3CHangup%2F%3E', {})).text();
        assert.match(bad, /not valid/);
    } finally { await s.close(); }
});

test('unknown routes are 404, including the removed ones', async () => {
    const s = await start();
    try {
        for (const path of ['/pending-call', '/register-token', '/hold-start', '/add-call', '/call']) {
            assert.equal((await s.request(path, { method: 'POST' })).status, 404, path);
        }
    } finally { await s.close(); }
});
