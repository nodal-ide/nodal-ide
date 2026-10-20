# Local Domains

Serve a project at `<name>.localhost` without editing `/etc/hosts`.

## Overview

A workspace can define one local domain per project in its settings. The app-owned nginx instance
routes the domain to a document root, PHP-FPM, or a loopback dev server. Domains are available only
while the local proxy is running, and nginx binds to loopback so nothing is exposed to the network.

Use Run > Open Local Site, or the status bar site menu, to open the domain in the default browser.

## Ports and HTTPS

By default, sites listen on high ports (`8080` for HTTP, `8443` for HTTPS). The portless mode uses
`80`/`443` through the embedded relay and requires the credential prompt when the relay starts.

HTTPS certificates come from an app-owned local certificate authority. Trust the authority from
Settings > Developer > Local Domains before using HTTPS; until it is trusted, browsers show a
certificate warning. High-port and portless URLs both use the same `.localhost` host.

## Host allowlists

Development servers commonly reject requests whose `Host` header is not `localhost` or
`127.0.0.1`. When proxying, nginx preserves the browser-facing host (`<name>.localhost`) and adds
`X-Forwarded-Host`, `X-Forwarded-Proto`, and `X-Forwarded-Port`, so the dev server must allow that
host. Add the workspace domain to the server's host allowlist, for example:

- Vite: `server.allowedHosts: ["myapp.localhost"]`.
- Next.js: `allowedDevOrigins: ["myapp.localhost"]` in `next.config.js`.
- Django: append `"myapp.localhost"` to `ALLOWED_HOSTS`.
- Rails: `config.hosts << "myapp.localhost"`.
- Laravel: set `APP_URL` and the relevant trusted-host settings to the site URL.

Avoid disabling host checks entirely; allowing only the project domain keeps the dev server
protected from DNS rebinding on the local network.

## WebSockets and hot reload

The proxy forwards `Upgrade` and `Connection` headers, uses HTTP/1.1 to the upstream, and applies
long read timeouts, so Vite, Next.js, and similar hot-reload WebSocket connections work through the
domain. If hot reload advertises a different host, port, or scheme, configure the dev server to use
the public site URL, and use `wss` when the site uses HTTPS.

## PHP sites

PHP sites require an installed runtime with a matching `php-fpm`. Choose the runtime and document
root in the workspace settings. With directory routing, nginx serves existing files and directories.
With front-controller routing, requests that do not match a file are sent to the entry file
(`index.php` by default).

## Troubleshooting

- The status bar shows whether the site is starting, running, or stopped; use Reveal Logs for nginx
  and PHP-FPM output.
- If a proxied site times out while starting, check the upstream task output: the domain starts only
  after the port accepts connections, and a failed start command rolls the site back.
- Settings > Developer > Local Domains shows tool versions, certificate state, and proxy
  diagnostics.
