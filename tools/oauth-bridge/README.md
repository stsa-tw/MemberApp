# OAuth redirect bridge

**The implementation lives in [`stsa-tw/MemberAppPage`](https://github.com/stsa-tw/MemberAppPage),
under `oauth-bridge/`, and is deployed to `app.stsa.tw`.** This file records why
it exists, because the reason lives here — in the apps that depend on it.

Two copies of a redirect endpoint would drift, and drift here means a login that
fails in production and nowhere else. So this directory holds no code.

## Why the apps need it

Both apps use the private-use scheme `tw.stsa.membership://callback` as their
OAuth redirect. authentik accepts it. **Indico does not** — its validator
(`indico/modules/oauth/forms.py`, confirmed on v3.3.12) is:

```python
_re = re.compile(r'^https?://(?P<host>[^/:]+)(?P<port>:[0-9]+)?(?P<path>/[^?]*)?$')
```

http and https only. So an https URL is registered with Indico instead, and it
302s to the app's scheme, carrying the authorization response across.

This is a gap in Indico, not in the apps: RFC 8252 §7.1 recommends private-use
schemes for native apps. Indico's own mobile client is a web app, so the case
never came up for them.

Rejected alternatives, for the record:

- **Loopback** (`http://127.0.0.1:PORT/`) passes Indico's regex, but AppAuth's
  loopback listener is `#if TARGET_OS_OSX`.
- **Universal Links / App Links** need Apple Developer configuration, and
  universal links are suppressed when the navigation happens inside the same
  app's `ASWebAuthenticationSession` — exactly our case.

## The endpoint

```
https://app.stsa.tw/oauth/app-callback
```

Register this verbatim as the redirect URI on the Indico OAuth application, and
configure the same value in both apps' Indico auth config.

## The gotcha that cost a review cycle

The Cloudflare route pattern **must** end in `*`:

```
app.stsa.tw/oauth/app-callback*
```

Cloudflare matches route patterns against the whole request URL including the
query string, and patterns may not contain query parameters — so a trailing
wildcard is the only way to match a URL that has one. Every real authorization
response has one. Without the wildcard the route matches nothing that actually
happens, and login fails every time.

It does not reproduce locally: `wrangler dev` ignores the routes table.

## Operational checks that are not in code

- No Cache Rule or Page Rule may match `/oauth/*`. The URL carries a single-use
  authorization code; a cached response breaks later logins.
- No full-URL logging on that path (Logpush datasets carrying `ClientRequestURI`).
  PKCE makes a leaked code useless on its own, but it should not sit in logs.
