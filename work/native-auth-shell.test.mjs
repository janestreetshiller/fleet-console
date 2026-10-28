import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import vm from 'node:vm';

const require = createRequire(import.meta.url);
const { createNativeAuthShell, renderNativeAuthShell } = require('./api/cloud.func/native-auth-shell.cjs');
const template = await readFile(new URL('./public/login.html', import.meta.url), 'utf8');
const policy = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self' https://identity.invalid https://github.com https://accounts.google.com http://127.0.0.1:48123; frame-ancestors 'none'; base-uri 'none'";
const nativePage = controls => `<!doctype html><html><head><style>body{background:white}</style></head><body><main><h1>Connect Ouros</h1><p>Your terminal is waiting. Connect this account to finish signing in.</p>${controls}<p>You can close this page when the terminal confirms.</p></main></body></html>`;
const signIn = nativePage(['github', 'google'].map(provider => `<form method="post" action="/auth/login"><input type="hidden" name="provider" value="${provider}"><button>Continue with ${provider}</button></form>`).join('') +
  '<form method="post" action="/auth/email/signin"><p><label>Email <input type="email" name="email" required></label></p><p><label>Password <input type="password" name="password" required></label></p><button>Sign in</button></form>');
const hidden = '<input type="hidden" name="client_id" value="ouros-desktop"><input type="hidden" name="response_type" value="code"><input type="hidden" name="code_challenge_method" value="S256">' +
  `<input type="hidden" name="code_challenge" value="${'c'.repeat(43)}"><input type="hidden" name="state" value="${'s'.repeat(43)}"><input type="hidden" name="redirect_uri" value="http://127.0.0.1:48123/auth/callback">`;
const consent = nativePage(`<form method="post" action="/auth/native/approve">${hidden}<button>Connect Ouros</button></form>`);
const htmlResponse = body => new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8',
  'content-security-policy': policy, 'cache-control': 'no-store', 'referrer-policy': 'no-referrer',
  'set-cookie': '__Host-ouros_session_native=synthetic; Path=/; HttpOnly; SameSite=Lax; Secure',
} });

test('shared device approval names Ouros without identifying every client as Ouros X', async () => {
  const forms = '<form method="post" action="/auth/device/verify"><input type="hidden" name="user_code" value="ABCD-EFGH"><button name="decision" value="approve">Connect Ouros X</button><button name="decision" value="deny">Deny</button></form>';
  const page = '<!doctype html><title>Connect Ouros X</title><h1>Connect Ouros X</h1><p>Confirm the code shown in Ouros X: <strong>ABCD-EFGH</strong>.</p>' + forms + '<p>Finish signing in here. Ouros X will connect automatically after you approve the matching device code.</p>';
  for (const method of ['GET', 'POST']) {
    const original = htmlResponse(page);
    original.headers.set('content-length', String(page.length));
    const response = await createNativeAuthShell(() => original)(new Request('https://ouros.md/auth/device/verify?user_code=ABCD-EFGH', { method }));
    const html = await response.text();
    assert.match(html, /<title>Connect to Ouros<\/title>/);
    assert.match(html, /Confirm the code shown in your app:/);
    assert.match(html, /Your app will connect automatically/);
    assert.ok(html.includes(forms.replace('>Connect Ouros X<', '>Connect to Ouros<')));
    assert.doesNotMatch(html, /Ouros X/);
    for (const header of ['set-cookie', 'cache-control', 'referrer-policy', 'content-security-policy']) assert.equal(response.headers.get(header), original.headers.get(header), header);
    assert.equal(response.headers.get('content-length'), null);
  }
});

test('device sign-in errors and expired codes retain actionable app-neutral recovery', async () => {
  for (const [path, copy] of [
    ['/auth/email/signin', 'Sign-in failed. Check your email and password, then try again.'],
    ['/auth/device/verify', 'This code is expired or has already been reviewed. Start a new connection in Ouros X.'],
    ['/auth/device/verify', 'Connected. Return to Ouros X; you can close this page.'],
  ]) {
    const page = '<title>Connect Ouros X</title><p role="status">' + copy + '</p>';
    const response = await createNativeAuthShell(() => htmlResponse(page))(new Request('https://ouros.md' + path, { method: 'POST' }));
    const html = await response.text();
    assert.doesNotMatch(html, /Ouros X/);
    assert.ok(html.includes(copy.replace('Ouros X', 'your app')));
  }
});

test('native sign-in reuses the approved login document, artwork and provider/email controls', () => {
  const html = renderNativeAuthShell(template, signIn);
  for (const asset of ['/design/system.css', '/design/content.css', '/design/auth-panel.css', '/design/fonts.css',
    '/design/global-navigation.css', '/design/serif/instrument-serif.woff2', '/design/demo/tiles/finder.webp']) {
    assert.ok(html.includes(asset), asset);
  }
  const panel = template.slice(template.indexOf('<div class="cell auth-entry-copy"'));
  assert.ok(html.endsWith(panel), 'approved artwork and remaining shell stay byte-identical');
  assert.match(html, /<body class="fin-site" data-biome="hero" data-site-frame>/);
  assert.match(html, /class="auth-entry-title">Connect Ouros/);
  assert.doesNotMatch(html, /data-session-pending|\/account-entry\.js|src="\/account\.js"|<style|\sstyle=/);
  const card = html.slice(html.indexOf('<div class="auth-card">'), html.indexOf('<div class="cell auth-entry-copy"'));
  assert.doesNotMatch(card, /data-provider="apple"|\sdisabled(?:[\s>])/);
  for (const provider of ['github', 'google']) {
    const exact = [...template.matchAll(/<form class="provider-form"[^>]*>[\s\S]*?<\/form>/g)].map(match => match[0]).find(value => value.includes(`data-provider="${provider}"`));
    assert.ok(exact && html.includes(exact.replace(/\sdisabled(?=[\s>])/g, '')), provider);
  }
  assert.match(html, /id="login-form" action="\/auth\/email\/signin" method="post"/);
  assert.match(html, /autocomplete="current-password" required/);
  assert.match(html, /class="btn btn-primary" type="submit">Sign in/);
});

test('native consent keeps the validated hidden fields in the approved login shell', () => {
  const html = renderNativeAuthShell(template, consent);
  assert.ok(html.includes(hidden));
  assert.match(html, /<form method="post" action="\/auth\/native\/approve">/);
  assert.match(html, /<button class="btn btn-primary" type="submit">Connect Ouros/);
  assert.doesNotMatch(html, /id="login-form"|name="password"|data-provider=/);
  assert.match(html, /class="cell auth-entry-copy"/);
});

test('the native response retains cookies, redirect and exact form origins with strict external assets', async () => {
  const request = new Request('https://ouros.md/auth/native/authorize?state=a%2Fb');
  const original = htmlResponse(signIn);
  original.headers.set('location', '/auth/native/authorize?state=a%2Fb');
  original.headers.set('content-length', '1');
  const handle = createNativeAuthShell(value => { assert.equal(value, request); return original; }, { template });
  const result = await handle(request);
  assert.equal(result.status, original.status);
  for (const name of ['set-cookie', 'location', 'cache-control']) assert.equal(result.headers.get(name), original.headers.get(name), name);
  assert.equal(result.headers.get('referrer-policy'), 'same-origin');
  assert.equal(result.headers.get('content-length'), null);
  const csp = result.headers.get('content-security-policy');
  assert.match(csp, /script-src 'self'; style-src 'self'/);
  assert.ok(csp.endsWith(policy.match(/form-action ([^;]+)/)[0]));
  assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval|\*/);
});

test('native error, callback, consent and ordinary auth responses pass through unchanged', async () => {
  for (const [path, method, original] of [
    ['/auth/native/authorize', 'GET', Response.json({ ok: false }, { status: 400 })],
    ['/auth/native/approve', 'POST', new Response(null, { status: 303, headers: { location: 'http://127.0.0.1:48123/auth/callback?code=fixture&state=fixture', 'referrer-policy': 'no-referrer' } })],
    ['/auth/callback', 'GET', Response.json({ ok: true })],
    ['/auth/email/signin', 'POST', Response.json({ ok: true, authenticated: true })],
    ['/auth/session', 'GET', Response.json({ ok: true })],
  ]) {
    const handle = createNativeAuthShell(() => original, { get template() { assert.fail('Other auth responses must not load the shell'); } });
    assert.equal(await handle(new Request('https://ouros.md' + path, { method })), original, path);
  }
});

test('the packaged settings adapter applies the approved shell after native authorization', async t => {
  const requireSettings = createRequire(new URL('./api/cloud.func/settings-handler.cjs', import.meta.url));
  const { createNodeHandler } = requireSettings('./settings-compatible.cjs');
  const module = { exports: {} };
  let observed;
  vm.runInNewContext(await readFile(new URL('./api/cloud.func/settings-handler.cjs', import.meta.url), 'utf8'), {
    module, URL, process: { env: {} }, __dirname: new URL('./api/cloud.func/', import.meta.url).pathname, console,
    require(name) {
      if (name !== './settings-compatible.cjs') return requireSettings(name);
      return { createNodeHandler, async createApplication() {
        return { handle(request) { observed = request.url; return htmlResponse(consent); }, async close() {} };
      } };
    },
  });
  const handler = module.exports.createHandler({ env: { OUROS_WEB_ORIGIN: 'https://ouros.md' } });
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await handler.close(); });
  const result = await fetch(`http://127.0.0.1:${server.address().port}/auth/native/authorize?state=a%2Fb`);
  assert.equal(result.status, 200);
  assert.equal(observed, 'https://ouros.md/auth/native/authorize?state=a%2Fb');
  assert.match(await result.text(), /class="auth-card"/);
  assert.match(result.headers.get('set-cookie'), /^__Host-ouros_session_native=synthetic;/);
  assert.equal(result.headers.get('referrer-policy'), 'same-origin');
  const config = JSON.parse(await readFile('vercel.json', 'utf8'));
  for (const name of ['api/cloud.mjs', 'api/gateway.mjs']) {
    const include = config.functions[name].includeFiles;
    assert.equal(typeof include, 'string', 'Vercel function includeFiles must be a single glob string');
    assert.ok(include.includes('public/login.html'), name);
  }
  assert.equal(config.functions['api/cloud.mjs'].includeFiles, '{api/cloud.func/release/**,public/login.html}', 'native appearance inclusion must preserve the authenticated release files');
  const ignore = await readFile('.vercelignore', 'utf8');
  assert.match(ignore, /!public\/login\.html/);
  assert.match(ignore, /!native-auth-shell\.test\.mjs/);
});
