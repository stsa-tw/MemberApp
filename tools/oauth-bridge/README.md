# OAuth redirect bridge

Indico only accepts `http(s)` redirect URIs, so `tw.stsa.membership://callback`
cannot be registered with it directly. A bridge is registered instead and
forwards to the app, carrying the authorization response across.

Two implementations, same behaviour. Deploy **one**.

| | `worker.js` (Cloudflare) | `wordpress-mu-plugin.php` |
|---|---|---|
| Runs | At the edge, before WordPress | Inside WordPress |
| In the request path | Nothing else | WP core, plugins, caching, security plugins |
| Setup | New Worker + a route | Copy one file |

Either works. The Worker keeps a credential-carrying request out of WordPress
entirely, which is why it is the default recommendation — but if WordPress is
where you already work, the plugin is fine as long as caching is handled.

## Option A — Cloudflare Worker

Dashboard → Workers & Pages → Create → paste `worker.js`. Add a route:

```
app.stsa.tw/oauth/ios-callback*
```

A dedicated subdomain rather than a path on `stsa.tw`, because:

- it keeps WordPress, its plugins and its caching entirely out of a request that
  carries an authorization code
- `/oauth/…` on the main site could later collide with a page, a rewrite rule or
  a redirect plugin; a separate host cannot
- cache and WAF policy can be set for the whole host without touching the site
- `*.stsa.tw` is already on the certificate, so there is no TLS work

`app.` specifically, so the same host can later serve
`/.well-known/apple-app-site-association` if universal links are ever needed,
and an App Store redirect for sharing.

## Option B — WordPress

Only applies if you serve the bridge from a path on `stsa.tw` instead of the
subdomain above; WordPress answers for the apex host, not for `app.`.

Copy `wordpress-mu-plugin.php` into `wp-content/mu-plugins/` (create the
directory if it does not exist). It loads automatically — there is nothing to
activate, and it survives theme and plugin changes.

It hooks `init` at priority 0, so it answers before WordPress resolves the URL
and 404s. No page or rewrite rule is needed. Change `STSA_BRIDGE_PATH` if you
use a different path.

## Verify (either option)

```bash
curl -sS -o /dev/null -D - "https://app.stsa.tw/oauth/ios-callback?code=test&state=abc"
```

Expected:

```
HTTP/2 302
location: tw.stsa.membership://callback?code=test&state=abc
cache-control: no-store
```

Then check that injected parameters are dropped — this should return the same
`Location` as above, with no `next`:

```bash
curl -sS -o /dev/null -D - "https://app.stsa.tw/oauth/ios-callback?code=test&state=abc&next=https://example.com"
```

## Caching will bite you if you let it

The response carries a one-time authorization code. If anything caches it, a
later login can be served someone else's code, or a stale one.

`no-store` is set, but confirm nothing overrides it:

- **Cloudflare**: no Cache Rule or Page Rule forcing cache on this path
- **WordPress**: exclude `/oauth/ios-callback` in WP Rocket / W3 Total Cache /
  LiteSpeed, if installed
- **Host-level**: some managed WordPress hosts cache aggressively at the edge
  regardless of headers — check for a bypass rule

The Worker sidesteps all of this, since it answers before any of it runs.

## Do not add a redirect parameter

The destination is a constant on purpose. The moment either version accepts a
`next=` or `redirect=` parameter, it becomes an open redirector attached to a
live OAuth flow — an attacker could have Indico hand an authorization code to a
host they control.

## Turn off query-string logging on this route

The code passes through the URL. PKCE means it is useless on its own — the
verifier never leaves the phone — but it should not sit in access logs.
