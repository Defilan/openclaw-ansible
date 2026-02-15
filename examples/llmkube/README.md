# LLMKube Integration for OpenClaw

These Kubernetes manifests deploy a local LLM (Qwen 3 32B) via [LLMKube](https://github.com/defilantech/llmkube) for use as OpenClaw's inference backend. This is entirely **optional** — OpenClaw works out of the box with cloud providers like Anthropic and OpenAI.

## Why Use a Local LLM?

- **Privacy**: No data leaves your network
- **Cost**: Zero per-token cost after hardware investment
- **Latency**: Low-latency inference on your LAN
- **Availability**: No dependency on external API uptime

## Prerequisites

- A Kubernetes cluster with GPU nodes (e.g., NVIDIA RTX 5060 Ti or better)
- [LLMKube operator](https://github.com/defilantech/llmkube) installed on the cluster
- NVIDIA GPU Operator / device plugin configured

## Manifests

| File | Description |
|------|-------------|
| `model.yaml` | Defines the Qwen 3 32B model (Q4_K_M quantization, 2x GPU) |
| `inferenceservice.yaml` | Creates the inference service with llama.cpp server |
| `nodeport-service.yaml` | Exposes the service on NodePort 30088 for LAN access |

## Deployment

```bash
kubectl apply -f model.yaml
kubectl apply -f inferenceservice.yaml
kubectl apply -f nodeport-service.yaml
```

Wait for the model to download and the inference pod to become ready:

```bash
kubectl get inferenceservices -w
```

## Connecting to OpenClaw

Once the service is running, configure your Ansible inventory to use it:

```yaml
# inventories/production/group_vars/all/main.yml

openclaw_model_primary: "llmkube/qwen3-32b"
openclaw_model_fallbacks:
  - "anthropic/claude-sonnet-4-5"

openclaw_custom_provider_enabled: true
openclaw_custom_provider_name: "llmkube"
openclaw_custom_provider_base_url: "http://host.docker.internal:30088/v1"
openclaw_custom_provider_api_key: "no-key-required"
openclaw_custom_provider_model_id: "qwen3-32b"
openclaw_custom_provider_model_name: "Qwen 3 32B"
openclaw_custom_provider_model_reasoning: false

# If OpenClaw runs in a Colima VM that can't reach LAN directly:
openclaw_llm_proxy_enabled: true
openclaw_llm_proxy_listen_port: 30088
openclaw_llm_proxy_target: "YOUR_K8S_NODE_IP:30088"
```

Then re-run:

```bash
make harden
make configure
```

## Customization

- **Different model**: Update `model.yaml` with a different GGUF source URL and adjust resource requests
- **Different port**: Change `nodePort` in `nodeport-service.yaml` and update `openclaw_llm_proxy_target` accordingly
- **Single GPU**: Set `gpu.count: 1` in `model.yaml` and `gpu: 1` in `inferenceservice.yaml`
