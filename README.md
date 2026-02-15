# OpenClaw Ansible

Ansible automation for deploying [OpenClaw](https://github.com/openclaw/openclaw) on a dedicated Mac Mini (or any macOS host). Handles the full lifecycle from base OS hardening through Docker deployment, security configuration, and ongoing maintenance.

## What You Get

- **Dedicated user account** with locked-down SSH access
- **macOS hardening**: firewall, stealth mode, disabled AirDrop/Bluetooth/AirPlay
- **Docker-based OpenClaw deployment** via Colima (no Docker Desktop required)
- **Security-first configuration**: gateway lockdown, auth tokens, consent mode, sandbox isolation
- **Optional local LLM integration** via [LLMKube](https://github.com/llmkube/llmkube)
- **Automated maintenance**: scheduled backups and health checks via launchd

## Prerequisites

- **Control machine**: macOS or Linux with Ansible 2.15+ and Python 3.10+
- **Target Mac Mini**: macOS 14+ (Sonoma) with an admin account and SSH enabled
- Install Ansible: `brew install ansible` or `pip install ansible`

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/openclaw-ansible.git
cd openclaw-ansible

# 2. Install Ansible Galaxy dependencies
make install-deps

# 3. Create your production inventory from the example
make init

# 4. Configure your deployment
#    Edit these files with your values:
$EDITOR inventories/production/group_vars/all/main.yml
$EDITOR inventories/production/group_vars/all/vault.yml

# 5. Encrypt your vault
ansible-vault encrypt inventories/production/group_vars/all/vault.yml

# 6. (Optional) Save vault password for convenience
echo 'your-vault-password' > .vault_password
chmod 600 .vault_password

# 7. Deploy
make site
```

## Architecture

```
openclaw-ansible/
├── ansible.cfg                          # Ansible configuration
├── Makefile                             # Convenient make targets
├── requirements.yml                     # Galaxy collection dependencies
│
├── inventories/
│   └── example/                         # Template inventory (committed)
│       ├── hosts.yml                    # Host connection details
│       └── group_vars/all/
│           ├── main.yml                 # All deployment variables
│           └── vault.yml.example        # Secret template (unencrypted)
│
├── playbooks/
│   ├── site.yml                         # Full deployment (all phases)
│   ├── setup.yml                        # Phase 1-2: OS + OpenClaw
│   ├── harden.yml                       # Phase 3-4: Security
│   ├── configure.yml                    # Phase 5-6: Integrations
│   └── maintain.yml                     # Phase 7: Maintenance
│
├── roles/
│   ├── macos_base/                      # macOS hardening + user creation
│   ├── homebrew/                        # Homebrew package management
│   ├── openclaw_deploy/                 # Clone, Docker setup, gateway start
│   ├── openclaw_harden/                 # Config hardening, env, sandbox, permissions
│   ├── openclaw_integrations/           # Custom providers, LLM proxy
│   ├── openclaw_browser/                # Browser automation (optional)
│   └── openclaw_maintain/               # Backups, health checks, launchd
│
├── examples/
│   └── llmkube/                         # Optional: K8s manifests for local LLM
│
└── docs/
    └── openclaw-mac-mini-setup-plan.md  # Detailed setup guide
```

## Deployment Phases

| Phase | Playbook | Roles | What It Does |
|-------|----------|-------|-------------|
| 1-2 | `setup.yml` | `macos_base`, `homebrew`, `openclaw_deploy` | Create user, harden macOS, install packages, deploy OpenClaw via Docker |
| 3-4 | `harden.yml` | `openclaw_harden` | Configure gateway auth, consent mode, sandbox, file permissions |
| 5-6 | `configure.yml` | `openclaw_integrations`, `openclaw_browser` | Custom LLM providers, socat proxy, browser automation |
| 7 | `maintain.yml` | `openclaw_maintain` | Scheduled backups, health checks, Google Drive sync |
| All | `site.yml` | All of the above | Full deployment in one run |

## Make Targets

```bash
make init           # Create production inventory from example
make install-deps   # Install Ansible Galaxy collections
make site           # Full deployment (all phases)
make setup          # Phase 1-2: OS prep + OpenClaw deployment
make harden         # Phase 3-4: Security hardening
make configure      # Phase 5-6: Integrations + browser
make maintain       # Phase 7: Maintenance tasks
make health-check   # Run health check only
make backup         # Run backup only
make vault-create   # Create a new encrypted vault file
make vault-edit     # Edit existing encrypted vault file
make lint           # Lint playbooks and roles
```

## Configuration Guide

### Inventory Structure

After `make init`, your production inventory lives at `inventories/production/` (gitignored). It contains:

- **`hosts.yml`** — Connection details (IP, user, password via vault references)
- **`group_vars/all/main.yml`** — All deployment variables (models, ports, toggles)
- **`group_vars/all/vault.yml`** — Encrypted secrets (passwords, API keys, IPs)

### Vault Workflow

Secrets are stored in an Ansible Vault file. The Makefile auto-detects your setup:

- **With `.vault_password` file**: Commands run without prompting
- **Without `.vault_password` file**: Commands prompt with `--ask-vault-pass`

```bash
# Create and encrypt vault from the example template
make vault-create

# Edit secrets later
make vault-edit

# Override vault method for any command
make harden VAULT_ARGS="--ask-vault-pass"
```

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `openclaw_model_primary` | `anthropic/claude-sonnet-4-5` | Primary LLM model |
| `openclaw_model_fallbacks` | `["openai/gpt-4o"]` | Fallback models |
| `openclaw_consent_mode` | `always` | Require approval for exec (`off`, `on-miss`, `always`) |
| `openclaw_gateway_mode` | `local` | Gateway bind mode |
| `openclaw_custom_provider_enabled` | `false` | Enable custom LLM provider |
| `openclaw_llm_proxy_enabled` | `false` | Enable socat LLM proxy |
| `openclaw_browser_enabled` | `false` | Enable browser automation |

## LLMKube Integration (Optional)

You can point OpenClaw at a local LLM running on your own GPU hardware via LLMKube. This keeps all inference on your network with zero per-token cost.

See [`examples/llmkube/README.md`](examples/llmkube/README.md) for Kubernetes manifests and configuration instructions.

To enable after deploying the K8s manifests:

1. Uncomment and configure the `openclaw_custom_provider_*` variables in your `main.yml`
2. Set `openclaw_custom_provider_enabled: true`
3. If your Mac Mini can't reach the K8s node directly (Colima VM networking), also enable the socat proxy:
   - Set `openclaw_llm_proxy_enabled: true`
   - Set `openclaw_llm_proxy_target: "YOUR_K8S_NODE_IP:30088"`
4. Run `make harden && make configure`

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Run `make lint` to check for issues
5. Submit a pull request

## License

[MIT](LICENSE)
