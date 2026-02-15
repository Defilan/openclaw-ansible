.PHONY: init setup harden configure maintain site health-check backup install-deps lint vault-create vault-edit

# --- Configuration ---
INVENTORY    ?= inventories/production
PLAYBOOK_DIR  = playbooks

# Auto-detect vault password file; fall back to interactive prompt
ifneq (,$(wildcard .vault_password))
  VAULT_ARGS ?=
  # ansible.cfg should have: vault_password_file = .vault_password
else
  VAULT_ARGS ?= --ask-vault-pass
endif

# --- First-Time Setup ---

# Copy example inventory to production and remind user to configure
init:
	@if [ -d "inventories/production" ]; then \
		echo "Error: inventories/production/ already exists. Remove it first to reinitialize."; \
		exit 1; \
	fi
	cp -r inventories/example inventories/production
	@cp inventories/production/group_vars/all/vault.yml.example \
	    inventories/production/group_vars/all/vault.yml
	@echo ""
	@echo "✅ Production inventory created at inventories/production/"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Edit inventories/production/hosts.yml with your Mac Mini connection details"
	@echo "  2. Edit inventories/production/group_vars/all/main.yml with your settings"
	@echo "  3. Edit inventories/production/group_vars/all/vault.yml with your secrets"
	@echo "  4. Encrypt the vault: ansible-vault encrypt inventories/production/group_vars/all/vault.yml"
	@echo "  5. (Optional) Save your vault password: echo 'your-password' > .vault_password"
	@echo "  6. Run: make install-deps && make site"
	@echo ""

# --- Ansible Galaxy ---

install-deps:
	ansible-galaxy collection install -r requirements.yml

# --- Playbooks ---

# Full initial setup (Phases 1-6)
site:
	ansible-playbook $(PLAYBOOK_DIR)/site.yml -i $(INVENTORY)/hosts.yml $(VAULT_ARGS)

# Phase 1-2: OS prep + OpenClaw deployment
setup:
	ansible-playbook $(PLAYBOOK_DIR)/setup.yml -i $(INVENTORY)/hosts.yml $(VAULT_ARGS)

# Phase 3-4: Security hardening
harden:
	ansible-playbook $(PLAYBOOK_DIR)/harden.yml -i $(INVENTORY)/hosts.yml $(VAULT_ARGS)

# Phase 5-6: Integrations + browser
configure:
	ansible-playbook $(PLAYBOOK_DIR)/configure.yml -i $(INVENTORY)/hosts.yml $(VAULT_ARGS)

# Phase 7: Maintenance tasks
maintain:
	ansible-playbook $(PLAYBOOK_DIR)/maintain.yml -i $(INVENTORY)/hosts.yml $(VAULT_ARGS)

# Run health check only
health-check:
	ansible-playbook $(PLAYBOOK_DIR)/maintain.yml -i $(INVENTORY)/hosts.yml $(VAULT_ARGS) --tags health_check

# Run backup only
backup:
	ansible-playbook $(PLAYBOOK_DIR)/maintain.yml -i $(INVENTORY)/hosts.yml $(VAULT_ARGS) --tags backup

# --- Linting ---

lint:
	ansible-lint playbooks/ roles/

# --- Vault Management ---

vault-create:
	ansible-vault create $(INVENTORY)/group_vars/all/vault.yml

vault-edit:
	ansible-vault edit $(INVENTORY)/group_vars/all/vault.yml
