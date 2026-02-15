#!/bin/bash
# Security scan — runs in CI to catch accidental secret/data leaks before merge.
# Exit codes: 0 = clean, 1 = leak detected
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

check() {
  local label="$1"
  local pattern="$2"

  echo "--- Checking: $label"
  if grep -rn --include='*.yml' --include='*.yaml' --include='*.j2' \
       --include='*.sh' --include='*.md' --include='*.cfg' --include='*.json' \
       "$pattern" "$REPO_ROOT" \
       --exclude-dir=.git --exclude-dir=tests; then
    echo "FAIL: $label"
    FAIL=1
  else
    echo "PASS"
  fi
  echo ""
}

echo "========================================"
echo "  OpenClaw Ansible — Security Scan"
echo "========================================"
echo ""

# 1. Production IP addresses (RFC1918 ranges that aren't generic examples)
#    We allow 192.168.1.1 (gateway), 192.168.1.50 (example static), 192.168.1.100 (example vault)
echo "--- Checking: Production IP leak (192.168.1.x, excluding known examples)"
if grep -rn --include='*.yml' --include='*.yaml' --include='*.j2' \
     --include='*.sh' --include='*.md' --include='*.cfg' --include='*.json' \
     -E '192\.168\.1\.[0-9]+' "$REPO_ROOT" \
     --exclude-dir=.git --exclude-dir=tests \
  | grep -v '192\.168\.1\.1"' \
  | grep -v '192\.168\.1\.50"' \
  | grep -v '192\.168\.1\.100"' \
  | grep -v 'YOUR_K8S_NODE_IP'; then
  echo "FAIL: Production IP leak"
  FAIL=1
else
  echo "PASS"
fi
echo ""

# 2. SSH private key material
check "SSH key material" "AAAAB3Nza"

# 3. API key patterns (real Anthropic, OpenAI, or generic secret patterns)
check "Anthropic API key" 'sk-ant-api03-[A-Za-z0-9]'
check "OpenAI API key" 'sk-[A-Za-z0-9]\{20,\}'

# 4. Hardcoded passwords (not vault references)
echo "--- Checking: Hardcoded passwords"
if grep -rn --include='*.yml' --include='*.yaml' \
     -E 'password:\s*"[^{"]' "$REPO_ROOT" \
     --exclude-dir=.git --exclude-dir=tests \
  | grep -v 'vault_' \
  | grep -v 'YOUR' \
  | grep -v 'changeme' \
  | grep -v 'ansible_ssh_pass' \
  | grep -v 'ansible_become_pass'; then
  echo "FAIL: Hardcoded passwords"
  FAIL=1
else
  echo "PASS"
fi
echo ""

# 5. Vault password file committed
echo "--- Checking: Vault password file"
if [ -f "$REPO_ROOT/.vault_password" ]; then
  echo "FAIL: .vault_password exists in repo"
  FAIL=1
else
  echo "PASS"
fi
echo ""

# 6. Encrypted vault file committed (should only be vault.yml.example)
echo "--- Checking: Encrypted vault files"
if find "$REPO_ROOT" -name "vault.yml" -not -path "*/tests/*" -not -path "*/.git/*" | grep -q .; then
  echo "FAIL: vault.yml found (only vault.yml.example should exist)"
  FAIL=1
else
  echo "PASS"
fi
echo ""

# 7. .env files committed
echo "--- Checking: .env files"
if find "$REPO_ROOT" -name ".env" -not -path "*/.git/*" -not -path "*/tests/*" | grep -q .; then
  echo "FAIL: .env file found in repo"
  FAIL=1
else
  echo "PASS"
fi
echo ""

# 8. Tasks handling secrets without no_log
echo "--- Checking: Secret-handling tasks missing no_log"
SECRET_TASKS_WITHOUT_NOLOG=0
for file in $(grep -rl 'openclaw_user_password\|_openclaw_auth_token\|openclaw_anthropic_api_key\|openclaw_openai_api_key\|openclaw_brave_search_api_key' \
  "$REPO_ROOT/roles/" --include='*.yml' 2>/dev/null); do
  # Only check tasks that write secrets (copy, template, command with password)
  # Uses Python for multi-line YAML analysis
  python3 -c "
import sys, re

with open('$file') as f:
    content = f.read()

# Split into task blocks (each starting with '- name:')
tasks = re.split(r'(?=^- name:)', content, flags=re.MULTILINE)

for task in tasks:
    # Skip set_fact and debug tasks (they don't write to disk/expose via process)
    if not task.strip():
        continue
    is_write_task = any(kw in task for kw in [
        'ansible.builtin.copy:', 'ansible.builtin.template:',
        'ansible.builtin.command:', 'ansible.builtin.shell:'
    ])
    has_secret = any(kw in task for kw in [
        'openclaw_user_password', '_final_config', 'openclaw.env.j2'
    ])
    has_nolog = 'no_log:' in task

    if is_write_task and has_secret and not has_nolog:
        task_name = re.search(r'- name:\s*(.+)', task)
        name = task_name.group(1) if task_name else 'unknown'
        print(f'MISSING no_log: {name} in $file')
        sys.exit(1)
" 2>/dev/null
  if [ $? -ne 0 ]; then
    SECRET_TASKS_WITHOUT_NOLOG=1
  fi
done

if [ "$SECRET_TASKS_WITHOUT_NOLOG" -eq 1 ]; then
  echo "FAIL: Tasks handling secrets without no_log: true"
  FAIL=1
else
  echo "PASS"
fi
echo ""

# Summary
echo "========================================"
if [ "$FAIL" -eq 0 ]; then
  echo "  All security checks PASSED"
  echo "========================================"
  exit 0
else
  echo "  Some security checks FAILED"
  echo "========================================"
  exit 1
fi
