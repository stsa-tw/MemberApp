/**
 * OAuth redirect bridge for the STSA iOS app.
 *
 * Indico only accepts http(s) redirect URIs — see the validator in
 * indico/modules/oauth/forms.py:
 *
 *     ^https?://(?P<host>[^/:]+)(?P<port>:[0-9]+)?(?P<path>/[^?]*)?$
 *
 * so the app's own `tw.stsa.membership://callback` is rejected outright. This
 * worker is registered with Indico instead, and forwards straight to the app.
 * It renders nothing and stores nothing.
 *
 * Deploy at:  https://app.stsa.tw/oauth/ios-callback
 * Register that exact URL as the redirect URI on the Indico OAuth application.
 */

const APP_CALLBACK = 'tw.stsa.membership://callback';

// Only the parameters an authorization server may send back. Copying the query
// string wholesale would forward anything an attacker appended.
const PASS_THROUGH = ['code', 'state', 'error', 'error_description', 'error_uri', 'iss'];

export default {
  async fetch(request) {
    const incoming = new URL(request.url);

    // The destination is fixed. Taking it from a parameter would turn this into
    // an open redirector hanging off the OAuth flow.
    const target = new URL(APP_CALLBACK);
    for (const key of PASS_THROUGH) {
      const value = incoming.searchParams.get(key);
      if (value !== null) target.searchParams.set(key, value);
    }

    return new Response(fallbackPage, {
      status: 302,
      headers: {
        Location: target.toString(),
        // The URL carries an authorization code. Keep it out of caches, and
        // out of the Referer sent to anything the fallback page links to.
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
        'Content-Type': 'text/html; charset=utf-8',
      },
    });
  },
};

// Shown only if the 302 does not open the app — an old iOS, or the link opened
// on a device without the app installed.
const fallbackPage = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>STSA</title>
<style>
  body { font: 16px/1.5 -apple-system, system-ui, sans-serif; margin: 0;
         display: grid; place-items: center; min-height: 100vh; padding: 24px;
         text-align: center; color: #201e1d; }
  p { color: #605d5d; }
</style>
<h1>回到 STSA App</h1>
<p>如果沒有自動跳轉，請手動切回 App。</p>
`;
