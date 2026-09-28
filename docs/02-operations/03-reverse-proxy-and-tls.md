---
title: Reverse proxy and TLS
description: Publish Logchef through Caddy or Nginx with HTTPS, secure cookies, and trusted proxy handling.
---

# Reverse proxy and TLS

Keep Logchef bound to `127.0.0.1` and let a reverse proxy own the public ports,
certificate, and client-facing hostname. The external URL must agree across the
proxy, Logchef, and the OIDC provider.

## Logchef settings

For `https://logs.example.com`, configure:

```nix
services.logchef = {
  listenAddress = "127.0.0.1";
  port = 8125;
  openFirewall = false;
  settings.server = {
    frontend_url = "https://logs.example.com";
    secure_cookie = true;
    trusted_proxies = [ "127.0.0.1" ];
  };
};
```

Only trust the exact address or CIDR from which the proxy connects. Logchef
ignores forwarded client addresses from other peers. If the proxy runs on a
different host, bind Logchef to a private interface, restrict the firewall to
that proxy, and replace `127.0.0.1` in `trusted_proxies` with its private
address.

## Caddy on NixOS

Caddy obtains and renews a public certificate automatically when the hostname
resolves to the host and ports 80 and 443 are reachable:

```nix
{
  services.caddy = {
    enable = true;
    virtualHosts."logs.example.com".extraConfig = ''
      reverse_proxy 127.0.0.1:8125
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

## Nginx on NixOS

The equivalent Nginx configuration uses ACME and overwrites forwarded headers
at the trusted boundary. Disabling proxy buffering lets live-tail events reach
the browser promptly:

```nix
{
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.com";
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."logs.example.com" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8125";
        extraConfig = ''
          proxy_buffering off;
          proxy_set_header X-Forwarded-For $remote_addr;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

## Verify the boundary

After rebuilding, verify both the private listener and public URL:

```console
ss -ltn | grep ':8125'
curl --fail http://127.0.0.1:8125/
curl --fail https://logs.example.com/
```

The first command should show `127.0.0.1:8125`, not `0.0.0.0:8125`. Confirm
that login returns to the HTTPS origin and that the session cookie is marked
`Secure`. For OIDC, register
`https://logs.example.com/api/v1/auth/callback` exactly; a different scheme,
host, path, or trailing slash is a different callback URL.
