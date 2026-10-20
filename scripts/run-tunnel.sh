#!/bin/sh
set -eu
# The token is read by cloudflared from a private file; never passed as a process argument.
config_dir="${DSH_REMOTE_CONFIG_DIR:-$HOME/.config/dsh-remote}"
cloudflared_bin="${CLOUDFLARED_BIN:-cloudflared}"
if [ ! -s "$config_dir/tunnel.token" ]; then
  echo 'Missing private tunnel.token; see docs/cloudflare.md.' >&2
  exit 1
fi
exec "$cloudflared_bin" tunnel --no-autoupdate run --token-file "$config_dir/tunnel.token"
