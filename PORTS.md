# Ports

Single source of truth for port allocation on the shared box. Before adding
a game or changing a port, check here first, pick something free, and
update this table in the same PR as the game's `.env` / `.env.example`.

After merging a port change, update `ufw_allowed_ports` in the
`infra-base` repo's `group_vars/all.yml` and re-run that playbook — this
file does not open the port by itself, it's just the record of what's in
use.

| Game         | Port  | Proto | Notes                          |
|--------------|-------|-------|---------------------------------|
| example-game | 27015 | udp   | placeholder, not actually open |

Reserved / do not use:

| Port | Reason                          |
|------|----------------------------------|
| 22   | SSH (or whatever `ssh_port` is set to in infra-base) |
