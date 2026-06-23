# Cloudflare Tunnel scripts

Helper for managing the local `tony-macbook-pro` Cloudflare Tunnel on macOS.

## Quick start

```bash
cd /Users/tonystark/desk/projects/pulse-energy

./scripts/cloudflare/tunnel.sh start
./scripts/cloudflare/tunnel.sh status
./scripts/cloudflare/tunnel.sh logs -f
```

## Commands

| Command | Description |
|---|---|
| `start` | Start the LaunchDaemon service |
| `stop` | Stop the LaunchDaemon service |
| `restart` | Restart without syncing config |
| `reload` | Copy `~/.cloudflared/` → `/etc/cloudflared/` and restart |
| `status` | Process list, tunnel info, IPv4/IPv6 health check |
| `logs [-f] [-n N]` | View `/Library/Logs/com.cloudflare.cloudflared.err.log` |
| `validate` | Validate ingress config and local backend ports |

## Optional: add to PATH

```bash
export PATH="$PATH:/Users/tonystark/desk/projects/pulse-energy/scripts/cloudflare"
```

Then run `tunnel.sh status` from anywhere.

## Full documentation

See [CLOUDFLARE_TUNNEL.md](../../pulse-energy-docs/docs/guides/CLOUDFLARE_TUNNEL.md).
