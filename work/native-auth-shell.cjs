'use strict';
const { readFile } = require('node:fs/promises');
const { resolve } = require('node:path');

// The approved login document owns artwork, layout, typography and controls.
// This adapter supplies only the already validated native authorization forms.
function renderNativeAuthShell(template, nativeHtml) {
  const main = nativeHtml.match(/<main>([\s\S]*?)<\/main>/)?.[1];
  const title = main?.match(/<h1>([\s\S]*?)<\/h1>/)?.[1];
  const introduction = main?.match(/<h1>[\s\S]*?<\/h1><p>([\s\S]*?)<\/p>/)?.[1];
  if (!main || !title || !introduction) throw new Error('Native authorization markup is unavailable');
  const forms = [...main.matchAll(/<form\b[^>]*>[\s\S]*?<\/form>/g)].map(match => match[0]);
  if (!forms.length) throw new Error('Native authorization controls are unavailable');
  const approvedProviders = [...template.matchAll(/<form class="provider-form"[^>]*>[\s\S]*?<\/form>/g)].map(match => match[0]);
  const emailForm = template.match(/<form id="login-form"[^>]*>[\s\S]*?<\/form>/)?.[0];
  let controls;
  const approval = forms.find(form => /action="\/auth\/native\/approve"/.test(form));
  if (approval) {
    // Keep the server's hidden PKCE/state/redirect fields byte-for-byte.
    controls = approval.replace('<button>', '<button class="btn btn-primary" type="submit">');
  } else {
    const providers = forms.filter(form => /action="\/auth\/login"/.test(form)).map(form => {
      const provider = form.match(/name="provider" value="([^"]+)"/)?.[1];
      const approved = approvedProviders.find(value => value.includes(`data-provider="${provider}"`));
      return approved ? approved.replace(/\sdisabled(?=[\s>])/g, '')
        : form.replace('<form ', '<form class="provider-form" ').replace('<button>', '<button class="btn btn-outline btn-provider" type="submit">');
    });
    if (!emailForm || !forms.some(form => /action="\/auth\/email\/signin"/.test(form)))
      throw new Error('Approved email authorization controls are unavailable');
    controls = `<div class="provider-row">${providers.join('')}</div><div class="divider">or continue with email</div>` +
      emailForm.replace('<form id="login-form"', '<form id="login-form" action="/auth/email/signin" method="post"').replace(/\sdisabled(?=[\s>])/g, '') +
      '<p class="fineprint"><a href="/signup" target="_blank" rel="noopener">Create account</a></p>';
  }
  const card = `<div class="auth-card"><h1 class="auth-entry-title">${title}</h1><p class="auth-entry-sub">${introduction}</p>${controls}<p class="fineprint">You can close this page when the terminal confirms.</p></div>`;
  const marker = /<div class="auth-card"[^>]*>[\s\S]*?<\/div><\/div><\/div><div class="cell auth-entry-copy"/;
  if (!marker.test(template)) throw new Error('Approved login shell is unavailable');
  return template.replace(marker, card + '</div></div><div class="cell auth-entry-copy"')
    .replace(/<title>[\s\S]*?<\/title>/, '<title>Ouros · Connect your account</title>')
    // Ordinary account scripts redirect to Dashboard. Native forms retain
    // their existing server-owned POST and callback/consent flow.
    .replace(/<script\b[^>]*src="\/(?:account-entry|account)\.js"[^>]*><\/script>/g, '')
    .replace(/<noscript>[\s\S]*?<\/noscript>/g, '');
}

function createNativeAuthShell(handle, options = {}) {
  let template;
  return async request => {
    const response = await handle(request);
    const destination = response.headers.get('x-ouros-auth-return');
    if (destination && response.status >= 200 && response.status < 300) {
      const origin = new URL(request.url);
      let target;
      try { target = new URL(destination, origin); } catch { return response; }
      const allowed = (destination.startsWith('/auth/native/authorize?') && target.pathname === '/auth/native/authorize') ||
        (destination.startsWith('/auth/device/verify?') && target.pathname === '/auth/device/verify');
      if (!allowed || target.origin !== origin.origin || target.username || target.password || target.hash) return response;
      const headers = new Headers(response.headers);
      headers.delete('x-ouros-auth-return'); headers.delete('content-type'); headers.delete('content-length');
      headers.set('location', target.pathname + target.search); headers.set('cache-control', 'no-store');
      await response.body?.cancel();
      return new Response(null, { status: 303, headers });
    }
    const path = new URL(request.url).pathname;
    if (['/auth/device/verify', '/auth/email/signin'].includes(path) && response.status === 200 &&
        response.headers.get('content-type')?.startsWith('text/html')) {
      const original = await response.clone().text();
      if (original.includes('<title>Connect Ouros X</title>')) {
        const html = original.replaceAll('Connect Ouros X', 'Connect to Ouros')
          .replaceAll('code shown in Ouros X:', 'code shown in your app:')
          .replaceAll('Ouros X will connect automatically', 'Your app will connect automatically')
          .replaceAll('Start a new connection in Ouros X.', 'Start a new connection in your app.')
          .replaceAll('Return to Ouros X;', 'Return to your app;');
        const headers = new Headers(response.headers);
        headers.delete('content-length');
        return new Response(html, { status: response.status, statusText: response.statusText, headers });
      }
    }
    if (request.method !== 'GET' || new URL(request.url).pathname !== '/auth/native/authorize' ||
        response.status !== 200 || !response.headers.get('content-type')?.startsWith('text/html')) return response;
    template ??= options.template !== undefined ? Promise.resolve(options.template)
      : readFile(resolve(__dirname, '../../public/login.html'), 'utf8');
    const html = renderNativeAuthShell(await template, await response.text());
    const headers = new Headers(response.headers);
    const formAction = headers.get('content-security-policy')?.match(/(?:^|;)\s*form-action\s+([^;]+)/)?.[1];
    if (!formAction) throw new Error('Native authorization form policy is unavailable');
    headers.set('content-security-policy', `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action ${formAction}`);
    // Native consent submits a same-origin HTML form. no-referrer would make
    // its Origin null, so the existing CSRF guard could not admit the POST.
    // The callback/consent redirect response retains its no-referrer policy.
    headers.set('referrer-policy', 'same-origin');
    headers.delete('content-length');
    return new Response(html, { status: response.status, statusText: response.statusText, headers });
  };
}
module.exports = { createNativeAuthShell, renderNativeAuthShell };
