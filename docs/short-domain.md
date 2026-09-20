# Serving the installer from a short domain (for the repository owner)

The raw GitHub URL always works:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh)
```

To make `https://dotfiles.rahmateka.my.id` return the same script, use two **Cloudflare Redirect Rules**. Nothing is
hosted on that domain: it only redirects to the raw file.

1. **DNS.** If the zone already has a wildcard `*` record that is **Proxied** (orange cloud), the subdomain already
   reaches Cloudflare and no record is needed. Otherwise add an `AAAA` record: name `dotfiles`, value `100::`, Proxied.
   The value is never contacted.
2. **Rules > Redirect Rules > Create rule.** Choose *Custom filter expression*, click *Edit expression* and paste the
   expression. Create both rules:

   | Rule name | Expression | Redirect to (Static, status 302) |
   |---|---|---|
   | `dotfiles install` | `(http.host eq "dotfiles.rahmateka.my.id" and http.request.uri.path eq "/")` | `https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh` |
   | `dotfiles uninstall` | `(http.host eq "dotfiles.rahmateka.my.id" and http.request.uri.path eq "/uninstall.sh")` | `https://raw.githubusercontent.com/rhmatzeka/dotfile/main/uninstall.sh` |

   Leave *Preserve query string* off and click *Deploy*.
3. **Check.**
   ```bash
   curl -fsSL https://dotfiles.rahmateka.my.id | head -3        # must print: #!/usr/bin/env bash
   curl -sI  https://dotfiles.rahmateka.my.id/uninstall.sh      # must answer 302 to raw.githubusercontent.com
   ```
   Cloudflare rules usually take effect within seconds. Until they exist the domain answers HTTP 526.

Why a redirect to the raw file rather than GitHub Pages: Cloudflare can inject scripts into HTML responses, which
would corrupt the installer. The raw file is plain text.

Note: `raw.githubusercontent.com` caches for about 5 minutes, so a fresh push can take that long to be served.
