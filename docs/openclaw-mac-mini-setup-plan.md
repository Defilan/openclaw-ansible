# OpenClaw on a Dedicated Mac Mini: Comprehensive Setup & Security Plan

## What You're Building

OpenClaw (formerly ClawdBot/MoltBot) is a self-hosted AI agent gateway that gives LLMs persistent access to your system — shell commands, file management, browser automation, and messaging platforms. It runs as an always-on daemon with a "Brain" (reasoning/API orchestration) and "Hands" (execution environment). Your 24GB Mac Mini is an excellent dedicated host for this.

Because OpenClaw has deep system access by design, running it on a *dedicated* machine (rather than your daily driver) is already one of the smartest moves you can make. This plan layers on additional isolation and hardening.

---

## Phase 1: Prepare the Mac Mini (Before Installing Anything)

### 1.1 — Fresh macOS Install

Even though the machine is only a couple months old, start clean. This gives you a known-good baseline with no leftover credentials or browser sessions that OpenClaw could accidentally access.

- Boot into Recovery (hold Power on Apple Silicon → Options → Reinstall macOS)
- Enable FileVault (full-disk encryption) during setup — this protects credentials and session data at rest
- Create a **primary admin account** you'll use for system administration only
- Set a strong unique password and enable the macOS firewall (System Settings → Network → Firewall → On)

### 1.2 — Create a Dedicated `openclaw` User Account

Don't run OpenClaw under your admin account. Create a Standard (non-admin) user:

```
System Settings → Users & Groups → Add User
- Name: openclaw
- Account type: Standard
- Strong password
```

This limits blast radius. If the agent is compromised, the attacker doesn't automatically get admin privileges, can't install system-wide software, and can't access your admin account's keychain.

### 1.3 — Network Configuration

Since this is a dedicated machine on your home network:

- **Assign a static IP** on your router (or via DHCP reservation) so you always know where it is
- **Disable unnecessary services**: Turn off AirDrop, AirPlay Receiver, Remote Management, and Bluetooth (System Settings → General → Sharing — turn everything off except what you explicitly need)
- **Consider VLAN isolation**: If your router supports it, put the Mac Mini on its own VLAN. This prevents a compromised OpenClaw from pivoting to your other machines, your GPU server, or your NAS. It can still reach the internet for API calls but can't scan your LAN
- If VLAN isn't an option, at minimum configure your router's firewall to block the Mac Mini from initiating connections to other local devices (except your GPU server if you plan to use local models via it)

### 1.4 — Install Prerequisites

Log into the `openclaw` user account for all remaining steps.

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js 22+ (required)
brew install node@22

# Install Docker Desktop for Mac
brew install --cask docker

# Verify
node --version   # Should be 22+
docker --version
```

---

## Phase 2: Docker-Based Deployment (Strongly Recommended)

Running OpenClaw in Docker is **the single most impactful security improvement** you can make. It sandboxes file access, shell execution, and network egress. Even the OpenClaw docs and every serious security guide recommend this approach.

### 2.1 — Clone and Build

```bash
cd ~
git clone https://github.com/openclaw/openclaw.git
cd openclaw

# Run the official Docker setup
./docker-setup.sh
```

This creates two important mount points:
- `~/.openclaw` — configuration, memory, API keys, agent settings
- `~/openclaw/workspace` — the agent's working directory (files it creates appear here)

### 2.2 — Onboard via Docker CLI

```bash
docker compose run --rm openclaw-cli onboard
```

During onboarding, make these choices:

- **Quick Start** is fine for initial setup; you'll harden the config afterward
- **Model provider**: You have several good options given your setup:
  - **Anthropic API** — Use Claude Sonnet or Opus. You're already a heavy Claude user, so this is familiar. Create a *dedicated API key* with spending limits just for OpenClaw
  - **Your local GPU server** — If your LLMKube setup exposes an OpenAI-compatible endpoint, you can point OpenClaw at it (manual config in `openclaw.json`). This keeps all inference on your own hardware with zero data leaving your network
  - **Google Gemini via OAuth** — Free tier option for experimentation
- **Chat platform**: Telegram is the easiest to set up and works well behind NAT. Discord and WhatsApp are also supported. Pick whichever you prefer for daily interaction

### 2.3 — Start the Gateway

```bash
docker compose up -d openclaw-gateway
```

Verify:
```bash
docker compose exec openclaw-gateway openclaw doctor
docker compose exec openclaw-gateway openclaw status
```

---

## Phase 3: Security Hardening (Critical)

This is where your plan goes from "it works" to "it's safe to actually use." OpenClaw has had real security incidents — the ClawHavoc event exposed 341 malicious skills on ClawHub, and a Snyk audit found nearly half of community skills had at least one security concern.

### 3.1 — Gateway Lockdown

Edit `~/.openclaw/openclaw.json`:

```json
{
  "gateway": {
    "bind": "127.0.0.1",
    "port": 18789,
    "auth": {
      "token": "<generate-with-openssl-rand-hex-32>"
    },
    "mode": "local"
  }
}
```

Key points:
- **Bind to 127.0.0.1 only** — never `0.0.0.0`. One user reported 400+ failed auth attempts in 6 hours after accidentally exposing the gateway
- **Set a strong auth token** — generate with `openssl rand -hex 32`
- **Mode "local"** — prevents remote gateway exposure

### 3.2 — Enable Consent Mode (Exec Approvals)

This is the most important setting for safe exploration. It requires your explicit approval before OpenClaw can execute write operations or shell commands:

```json
{
  "tools": {
    "exec": {
      "ask": "on"
    }
  }
}
```

Start with consent mode **on**. As you build trust and understand the agent's behavior patterns, you can selectively relax this for specific, well-tested workflows.

### 3.3 — Sandbox Configuration

Since you're running Docker, enable sandbox isolation for all non-main sessions:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "enabled": true,
        "mode": "non-main",
        "scope": "session",
        "workspaceAccess": "none",
        "docker": {
          "network": "none",
          "image": "openclaw-sandbox:bookworm-slim"
        }
      }
    }
  }
}
```

Build the sandbox image:
```bash
./scripts/sandbox-setup.sh
```

The `network: "none"` setting means sandbox containers have **no internet access** — this prevents a prompt injection from exfiltrating data. Only enable networking for specific agents/tasks that genuinely need it.

### 3.4 — DM Scope Isolation

This is critical if anyone else could message your bot (even accidentally):

```json
{
  "session": {
    "dmScope": "per-peer"
  }
}
```

The default `main` scope shares one session across all DMs — environment variables, API keys, and conversation history from one person are visible to anyone else who messages the bot. Set `per-peer` at minimum.

### 3.5 — Disable mDNS Broadcasting

OpenClaw broadcasts its presence on your local network by default, including filesystem paths and SSH availability:

```bash
export OPENCLAW_DISABLE_BONJOUR=1
```

Or in config:
```json
{
  "gateway": {
    "mdns": "minimal"
  }
}
```

### 3.6 — File Permissions

```bash
chmod 700 ~/.openclaw
chmod 600 ~/.openclaw/credentials/whatsapp/*/creds.json 2>/dev/null
chmod 600 ~/.openclaw/agents/*/agent/auth-profiles.json 2>/dev/null
```

Treat `~/.openclaw` like a password vault — the official documentation says exactly this.

### 3.7 — API Key Hygiene

- **Create dedicated API keys** for OpenClaw with spending limits. Never reuse keys from Claude Code or your other tools
- **Store keys in environment variables**, not in config files:
  ```bash
  # In your .env file (never commit to git)
  ANTHROPIC_API_KEY=sk-ant-...
  OPENCLAW_AUTH_TOKEN=$(openssl rand -hex 32)
  ```
- **Set monthly budget caps** on your Anthropic, OpenAI, or other provider dashboards
- **Rotate keys monthly** — mark it on your calendar

---

## Phase 4: Prompt Injection Defense

This is the threat model unique to AI agents. Someone (or some website) can embed hidden instructions in text the agent reads — emails, web pages, documents — that trick it into taking unauthorized actions.

### 4.1 — Practical Mitigations

- **Don't connect email/CRM initially** — prompt injection via malicious emails is one of the most cited attack vectors. A bad actor sends a carefully crafted email, OpenClaw reads it, and the hidden instructions trigger unintended actions
- **Use modern, instruction-hardened models** — Claude Sonnet 4.5 or Opus are significantly more resistant to injection than older models. The OpenClaw docs explicitly recommend this
- **Be cautious with web browsing** — when OpenClaw fetches web content, treat it as untrusted. The sandbox helps here
- **Review skills before installing** — more on this below

### 4.2 — Skill Vetting

Skills are the #1 attack vector. They're essentially code that runs on your machine:

- **Never install skills from ClawHub without reading the source code first**
- Verify the author's reputation and check for community reviews
- Pin skill versions — don't auto-update
- Start with zero third-party skills and only add them one at a time as you verify them
- Run `openclaw doctor` after installing any new skill

---

## Phase 5: Leveraging Your Existing Infrastructure

Given your setup (Claude Code, ChatGPT, dual-GPU server with LLMKube), here's how to make OpenClaw complement rather than duplicate your workflow:

### 5.1 — Model Failover Configuration

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5",
        "fallbacks": ["openai/gpt-4o", "local/your-llmkube-model"]
      }
    }
  }
}
```

### 5.2 — Using Your Local GPU Server

If your LLMKube instance exposes an OpenAI-compatible API, you can configure OpenClaw to use it. This is the most private option — no data leaves your network:

```json
{
  "providers": {
    "custom": {
      "baseUrl": "http://<your-gpu-server-ip>:8000/v1",
      "apiKey": "your-local-key"
    }
  }
}
```

If you go this route and your Mac Mini is on a separate VLAN, you'll need a firewall rule allowing it to reach the GPU server's API port.

### 5.3 — Complementary Workflows

- **Claude Code** → your interactive coding sessions, pair programming
- **OpenClaw** → persistent, always-on automations: monitoring, scheduling, research tasks, file management, message triage
- **Local LLMs** → private inference for sensitive tasks, cost savings on high-volume routine work

---

## Phase 6: Browser Automation (Optional, Higher Risk)

OpenClaw can control a dedicated browser instance via Chrome DevTools Protocol. This is powerful but increases your attack surface significantly.

### 6.1 — If You Enable It

```json
{
  "browser": {
    "enabled": true,
    "defaultProfile": "openclaw",
    "headless": false,
    "profiles": {
      "openclaw": {
        "cdpPort": 18792,
        "color": "#FF6B00"
      }
    }
  }
}
```

The managed browser uses an **isolated Chrome profile** — it never touches your personal browser data. The orange tint visually distinguishes the agent's browser from yours.

### 6.2 — Browser Safety Rules

- Never log the agent browser into accounts that have access to financial services, your primary email, or admin panels
- Create dedicated/burner accounts for any service the agent needs to interact with
- Keep browser automation within the sandbox when possible
- Build the browser sandbox image for additional isolation:
  ```bash
  ./scripts/sandbox-browser-setup.sh
  ```

---

## Phase 7: Ongoing Maintenance

### 7.1 — Regular Health Checks

```bash
# Run weekly
docker compose exec openclaw-gateway openclaw doctor
docker compose exec openclaw-gateway openclaw doctor --deep

# Monitor logs
docker compose exec openclaw-gateway openclaw logs --follow
```

### 7.2 — Update Strategy

- **Don't auto-update** — new versions may change security defaults
- Check release notes before updating
- Back up `~/.openclaw` before any upgrade
- After updating, re-run `openclaw doctor` and verify your hardening config wasn't reset

### 7.3 — Backup Strategy

```bash
# Weekly backup of config and agent state
tar czf ~/openclaw-backup-$(date +%Y%m%d).tar.gz ~/.openclaw
```

Store backups encrypted and off the Mac Mini (iCloud Drive with Advanced Data Protection, or your NAS).

### 7.4 — Monitoring Checklist

- [ ] Review `openclaw doctor` output weekly
- [ ] Check API spending dashboards weekly
- [ ] Rotate API keys monthly
- [ ] Review session logs for unexpected tool usage
- [ ] Check for OpenClaw security advisories
- [ ] Audit any installed skills after updates

---

## Quick-Start Order of Operations

1. Fresh macOS install with FileVault on the Mac Mini
2. Create the dedicated `openclaw` Standard user account
3. Network isolation (static IP, disable unused services, VLAN if possible)
4. Install Node.js 22, Docker Desktop
5. Clone repo and run `docker-setup.sh`
6. Onboard with Docker CLI — pick your model provider and chat platform
7. **Before using it**: Apply all Phase 3 hardening (gateway bind, auth token, consent mode, sandbox, DM scope, mDNS, file permissions, dedicated API keys)
8. Build the sandbox image
9. Start the gateway and verify with `openclaw doctor`
10. Start with TUI or Telegram — no third-party skills, consent mode on
11. Gradually expand capabilities as you build confidence

---

## Risk Summary

| Risk | Mitigation |
|------|-----------|
| Malicious skills / supply chain attack | Zero third-party skills initially; vet source code before installing |
| Prompt injection via web/email | Don't connect email; sandbox web browsing; use modern models |
| Gateway exposed to network | Bind to 127.0.0.1; strong auth token; disable mDNS |
| API key theft / overspending | Dedicated keys with spending limits; env vars not config files |
| Lateral movement to other machines | VLAN isolation; dedicated non-admin user account |
| Data leakage via session sharing | `per-peer` DM scope; sandbox with `workspaceAccess: none` |
| Credential exposure at rest | FileVault; `chmod 700` on `.openclaw`; encrypted backups |
| Rogue exec / destructive commands | Consent mode on; start read-only and expand gradually |
