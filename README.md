# IAC-MAAS – Bare-Metal Provisioning

> MAAS = Infrastructure Bootloader. Ansible = Infrastructure Brain. Git = Infrastructure Memory.

## Zweck

Dieses Repository bildet die **Hardware-Provisionierungsschicht** ab.
Es arbeitet ausschließlich mit [IAC-Ansible](https://github.com/bauer-group/IAC-Ansible) zusammen.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        GESAMTARCHITEKTUR                                 │
│                                                                          │
│  ┌─────────┐    ┌──────────┐    ┌───────────┐    ┌──────────────────┐   │
│  │Hardware  │───>│  MAAS    │───>│ cloud-init│───>│  IAC-Ansible     │   │
│  │Power-On  │    │ (dieses  │    │ Übergabe  │    │  (Config Mgmt)   │   │
│  │          │    │  Repo)   │    │           │    │  github.com/     │   │
│  └─────────┘    └──────────┘    └───────────┘    │  bauer-group/    │   │
│                                                   │  IAC-Ansible     │   │
│  IAC-MAAS Verantwortung ◄──────────────────────► │                  │   │
│  endet hier                                       └──────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

## Verantwortungsgrenzen

| Thema | IAC-MAAS | IAC-Ansible |
|-------|----------|-------------|
| Hardware-Erkennung | ✅ | - |
| PXE Boot / OS Install | ✅ | - |
| IPMI / Power Control | ✅ | - |
| SSH-Key Injection | ✅ | - |
| cloud-init Übergabe | ✅ | - |
| Node-Identity / Facts | Setzt Metadata | Liest Metadata |
| Ansible Bootstrap | install.sh | Alles weitere |
| Service-Konfiguration | - | ✅ |
| Security Hardening | - | ✅ |
| Monitoring Setup | - | ✅ |
| Kubernetes | - | ✅ |
| Patch-Management | - | ✅ |

## Repository-Struktur

```
IAC-MAAS/
├── README.md
├── config.env                       # Zentrale Konfiguration (MUSS angepasst werden)
├── docs/
│   └── DEPLOYMENT-GUIDE.md          # Vollständige Anleitung für DevOps
├── maas/
│   ├── scripts/
│   │   ├── bootstrap-maas.sh        # MAAS Installation
│   │   ├── configure-network.sh     # VLAN/Subnet/DHCP Setup
│   │   ├── import-images.sh         # OS Image Sync
│   │   ├── deploy-machine.sh        # Deploy Wrapper (CLI)
│   │   ├── register-machine.sh      # Neue Hardware registrieren
│   │   └── api-helpers.sh           # Utility Functions
│   ├── configs/
│   │   ├── maas-settings.yaml       # Konfigurationsreferenz
│   │   ├── tags.yaml                # Tag-Definitionen → Ansible-Gruppen
│   │   └── commissioning-scripts/
│   │       └── check-firmware.sh
│   └── hooks/
│       └── post-deploy-verify.sh    # Verifikation nach Deploy
├── cloud-init/
│   └── templates/
│       └── base.yaml                # Einziges Template: Identity + Ansible Bootstrap
├── terraform/                       # Deklaratives Deployment (optional)
│   ├── modules/maas-machine/
│   └── environments/
├── network/
│   └── NETWORK-SEGMENTATION.md      # Netzwerk-Segmentierung (herstellerunabhängig)
└── ansible-additions/               # Dateien für IAC-Ansible Integration
    ├── INTEGRATION.md               # Integrationsanleitung
    ├── site-pull.yml                # ansible-pull Entrypoint
    ├── roles/                       # 4 neue Rollen
    ├── inventory/maas/              # Dynamic Inventory
    ├── group_vars/                  # Tag-basierte Variablen
    ├── callback_plugins/            # MAAS Feedback
    ├── filter_plugins/              # Custom Jinja2 Filter
    └── playbooks/                   # Operational Playbooks
```

## Quick Start

```bash
# 1. Repo klonen
git clone git@github.com:bauer-group/IAC-MAAS.git
cd IAC-MAAS

# 2. Konfiguration anpassen (Organisation, Netzwerk, DNS, etc.)
vim config.env

# 3. MAAS Server aufsetzen
sudo bash maas/scripts/bootstrap-maas.sh

# 4. Netzwerk konfigurieren
bash maas/scripts/configure-network.sh

# 5. Hardware PXE-booten → Commissioning automatisch
# 6. Tags setzen, deployen
bash maas/scripts/deploy-machine.sh <SYSTEM_ID> noble
```

## Integration mit IAC-Ansible

Nach dem Deploy durch MAAS passiert folgendes automatisch:

1. cloud-init schreibt Node-Metadata nach `/etc/bauer-group/node-identity.json`
2. cloud-init führt IAC-Ansible `install.sh` aus (installiert Ansible + systemd-Timer)
3. Ansible liest die Identity, bestimmt anhand der MAAS-Tags die Rolle
4. systemd-Timer führt `ansible-pull` alle 30 Minuten aus (Drift-Correction)

Es gibt **ein einziges** cloud-init Template (`base.yaml`). Die gesamte Rollenzuweisung
(K8s, Monitoring, Storage, etc.) erfolgt ausschließlich durch Ansible anhand der MAAS-Tags.

Für Details siehe [docs/DEPLOYMENT-GUIDE.md](docs/DEPLOYMENT-GUIDE.md).
