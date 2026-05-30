# 🔐 DevSecOps Pipeline Suite

A fully automated, containerized DevSecOps laboratory that orchestrates **HashiCorp Vault**, **GitLab CE**, **DefectDojo**, and **Grafana** into a unified, end-to-end security pipeline — spun up with a single command.

---

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Docker Host                            │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌────────────────────┐    │
│  │  Vault   │───▶│  GitLab  │───▶│    GitLab Runner   │    │
│  │ :8200    │    │  :9500   │    │  (CI/CD executor)  │    │
│  └──────────┘    └──────────┘    └────────────────────┘    │
│       │                │                   │                │
│       │         ┌──────▼──────┐            │                │
│       │         │  Registry   │            │                │
│       │         │   :5002     │            │                │
│       │         └─────────────┘            │                │
│       │                                    ▼                │
│       │                          ┌─────────────────┐        │
│       └─────────────────────────▶│   DefectDojo    │        │
│                                  │     :8080       │        │
│                                  └────────┬────────┘        │
│                                           │                 │
│                                  ┌────────▼────────┐        │
│                                  │     Grafana     │        │
│                                  │     :3000       │        │
│                                  └─────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Pipeline Flow

```
Code Push ──▶ GitLab CI ──▶ Semgrep SAST ──▶ DefectDojo ──▶ Security Gate ──▶ Telegram Alert
                                                  │
                                             Grafana Dashboard
```

---

## 🧰 Stack

| Component | Role | Port |
|-----------|------|------|
| **HashiCorp Vault** | Central secret store for all tokens & credentials | `8200` |
| **GitLab CE 17.x** | Self-hosted SCM and CI/CD engine | `9500` |
| **GitLab Container Registry** | Stores custom SAST tool images | `5002` |
| **GitLab Runner** | Executes pipeline jobs | — |
| **DefectDojo** | Vulnerability aggregation and management | `8080` |
| **Grafana** | Dashboard for DefectDojo metrics via Postgres | `3000` |
| **Semgrep** | Static Application Security Testing (SAST) | — |
| **Telegram Bot** | Security gate notifications | — |

---

## 📁 Project Structure

```
devsecops-pipeline/
├── .env                        # Environment configuration
├── bootstrap.sh                # Master orchestration script
├── docker-compose.yml          # Compose entry point (includes sub-composes)
└── scripts/
    ├── setup/
    │   ├── install_dependencies.sh
    │   ├── install_docker.sh
    │   ├── insecure_reg.sh     # Configures insecure Docker registry
    │   └── cleanup_project.sh
    ├── vault/
    │   ├── vault.yml           # Vault Docker Compose definition
    │   └── vault_inject.sh     # Seeds all secrets into Vault
    ├── gitlab/
    │   ├── gitlab.yml          # GitLab Docker Compose definition
    │   ├── gitlab_config.sh    # GitLab instance configuration
    │   ├── gitlab_users_projects.sh  # Creates users and imports projects
    │   └── gitlab_runner.sh    # Registers GitLab Runner
    ├── dojo/
    │   └── dojo_setup.sh       # DefectDojo product/engagement bootstrap
    ├── grafana/
    │   └── grafana.yml         # Grafana Docker Compose definition
    └── pipeline/
        └── ci_setup.sh         # Pushes .gitlab-ci.yml to target project
```

---

## ⚙️ CI/CD Pipeline Stages

The `gitlab-ci.yml` defines a three-stage security pipeline that runs against an imported Django application:

**Stage 1 — `test`**: Runs **Semgrep SAST** using a custom image from the self-hosted registry, producing a `gl-sast-report.json` artifact.

**Stage 2 — `upload`**: Pushes the SAST report to **DefectDojo** via its `reimport-scan` REST API, auto-creating the product and engagement context.

**Stage 3 — `gate`**: Queries DefectDojo for active High-severity findings. If any are found, a formatted **Telegram alert** is sent with the vulnerability list. The pipeline passes or fails accordingly.

---

## 🚀 Quick Start

### Prerequisites

- Ubuntu 22.04+ host (bare metal or VM)
- At least **8 GB RAM** and **40 GB disk** (GitLab and DefectDojo are resource-intensive)
- Internet access for pulling Docker images
- A Telegram bot token and chat ID (for alerts)

### 1. Clone the Repository

```bash
git clone https://github.com/nargiz5/devsecops-pipeline.git
cd devsecops-pipeline
```

### 2. Configure Environment

Edit `.env` with your own values:

```bash
nano .env
```

The key variables to change:

```ini
HOST_IP=<your-server-ip>
VAULT_URL=http://<your-server-ip>:8200

# Credentials — change all defaults before deploying
ROOT_PASSWORD=<strong-password>
ADMIN_PASSWORD=<strong-password>
DOJO_ADMIN_PASSWORD=<strong-password>

# Telegram notifications
TELEGRAM_BOT_TOKEN=<your-bot-token>
TELEGRAM_CHAT_ID=<your-chat-id>
```

> **Note:** The `.env` file is intentionally committed in this lab for reproducibility. In production environments, use your secrets manager or CI/CD variable store instead.

### 3. Run the Bootstrap

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script will automatically:

1. Install OS dependencies and Docker
2. Configure the insecure Docker registry
3. Start and unseal **Vault**, then inject all secrets
4. Start **GitLab** and wait for it to become healthy
5. Configure GitLab users, import the target project, and register the runner
6. Bootstrap **DefectDojo** with a product and engagement
7. Start **Grafana** and connect it to the DefectDojo Postgres database
8. Push the CI pipeline to the imported project

### 4. Access the Services

Once the bootstrap completes, all services are available at:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| GitLab | `http://<HOST_IP>:9500` | `adminuser` / see `.env` |
| DefectDojo | `http://<HOST_IP>:8080` | `admin` / see `.env` |
| Vault UI | `http://<HOST_IP>:8200` | Token: `myroot` |
| Grafana | `http://<HOST_IP>:3000` | `admin` / `admin` |

---

## 🔑 Secret Management

All sensitive tokens (DefectDojo API key, GitLab tokens, Docker credentials) are stored in **HashiCorp Vault** and injected at runtime by the pipeline scripts. The `vault_inject.sh` script seeds Vault with the initial values from `.env` during bootstrap.

This means no credentials are hardcoded in scripts — they are retrieved from Vault via the `VAULT_TOKEN` at runtime.

---

## 🔔 Telegram Notifications

The security gate stage sends a Telegram message after every pipeline run:

- ✅ **PASSED** — no active High findings in DefectDojo
- 🚨 **ALERT** — one or more High findings detected, with titles listed

To set up a bot: use [@BotFather](https://t.me/BotFather) on Telegram, create a bot, and obtain the token and your chat ID.

---

## ⚠️ Security Notes

This project is designed as a **lab environment**. Before using it in any shared or production context:

- Rotate all credentials in `.env` and add `.env` to `.gitignore`
- Replace the hardcoded `VAULT_TOKEN=myroot` with a properly initialized and unsealed Vault setup
- Move CI/CD secrets (Telegram token, DefectDojo API key) to **GitLab CI/CD masked variables**
- Enable TLS on all service endpoints
- Restrict network access to the host

---

## 📄 License

This project is intended for educational and lab use.
