<?php
/**
 * Plugin Name: STSA OAuth Redirect Bridge
 * Description: Forwards Indico's OAuth callback to the STSA iOS app.
 *
 * Indico only accepts http(s) redirect URIs — see the validator in
 * indico/modules/oauth/forms.py:
 *
 *     ^https?://(?P<host>[^/:]+)(?P<port>:[0-9]+)?(?P<path>/[^?]*)?$
 *
 * so `tw.stsa.membership://callback` cannot be registered with it directly.
 * This endpoint is registered instead and forwards to the app.
 *
 * Install: drop into wp-content/mu-plugins/ (create the directory if needed).
 * mu-plugins load automatically, cannot be deactivated by accident, and
 * survive theme and plugin changes.
 */

defined('ABSPATH') || exit;

const STSA_BRIDGE_PATH = '/oauth/ios-callback';
const STSA_APP_CALLBACK = 'tw.stsa.membership://callback';

// Only the parameters an authorization server may send back. Forwarding the
// query string wholesale would pass along anything an attacker appended.
const STSA_BRIDGE_PARAMS = ['code', 'state', 'error', 'error_description', 'error_uri', 'iss'];

add_action('init', function () {
    $path = strtok($_SERVER['REQUEST_URI'] ?? '', '?');
    if (rtrim($path, '/') !== STSA_BRIDGE_PATH) {
        return;
    }

    // The destination is a constant. Taking it from a parameter would make this
    // an open redirector sitting in a live OAuth flow.
    $params = [];
    foreach (STSA_BRIDGE_PARAMS as $key) {
        if (isset($_GET[$key]) && is_string($_GET[$key])) {
            $params[$key] = $_GET[$key];
        }
    }

    $target = STSA_APP_CALLBACK;
    if ($params) {
        $target .= '?' . http_build_query($params);
    }

    // Deliberately not wp_redirect(): it sanitises the URL against a scheme
    // allowlist and would strip a private-use scheme entirely.
    nocache_headers();
    header('Location: ' . $target, true, 302);
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Referrer-Policy: no-referrer');

    // Shown only if the redirect does not open the app.
    echo '<!doctype html><meta charset="utf-8">'
       . '<meta name="viewport" content="width=device-width, initial-scale=1">'
       . '<title>STSA</title>'
       . '<p style="font:16px/1.5 -apple-system,system-ui,sans-serif;text-align:center;padding:40px">'
       . '如果沒有自動跳轉，請手動切回 STSA App。</p>';
    exit;
}, 0);
