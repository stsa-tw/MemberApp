# OAuth redirect bridge

Indico only accepts `http(s)` redirect URIs, so `tw.stsa.membership://callback`
cannot be registered with it directly. This worker is registered instead and
forwards to the app, preserving the authorization response.

## Deploy

Cloudflare dashboard → Workers & Pages → Create → paste `worker.js`.

Then add a route so it serves the callback path:

```
stsa.tw/oauth/ios-callback*
```

Test it — this should answer `302` with a `Location` of
`tw.stsa.membership://callback?code=test&state=abc`:

```bash
curl -sS -o /dev/null -D - "https://stsa.tw/oauth/ios-callback?code=test&state=abc"
```

## Turn off query-string logging on this route

The URL carries an authorization code. PKCE means the code alone is useless —
the verifier never leaves the phone — but it still should not sit in logs.

In Cloudflare, check that Logpush / Analytics are not retaining full URLs for
this route, and that no Page Rule adds query strings to the cache key.

## Do not add a redirect parameter

`APP_CALLBACK` is a constant on purpose. The moment this accepts a `next=` or
`redirect=` parameter, it becomes an open redirector attached to a live OAuth
flow — an attacker could have Indico hand an authorization code to a host they
control.
