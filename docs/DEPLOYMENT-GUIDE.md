# MAAS + Ansible Deployment Guide

> Vollständige Anleitung für den DevOps Engineer.
> Deckt IAC-MAAS und die nötigen Ergänzungen in IAC-Ansible ab.

---

## 1. Architektur-Übersicht

### 1.1 Zwei Repositories – Ein System

```
IAC-MAAS (dieses Repo)              IAC-Ansible (bestehendes Repo)
========================             ============================
Hardware-Erkennung                   Node-Identity auswerten
PXE/Network Boot                    Rollen zuweisen
OS-Installation                      Pakete installieren
cloud-init Injection                 Services konfigurieren
Power-Control (IPMI)                 Security Hardening
Node-Metadata setzen                 Monitoring aufsetzen
                                     Kubernetes deployen
        │                            Patch-Management
        │                                    ▲
        └──── cloud-init ──── install.sh ────┘
```

### 1.2 Der vollständige Lifecycle einer Maschine

```
Phase 1: MAAS (IAC-MAAS)
─────────────────────────
  1. Hardware einschalten (IPMI oder manuell)
  2. PXE Boot → DHCP → iPXE
  3. Commissioning (Hardware-Tests)
  4. Status: Ready
  5. Deploy-Befehl (manuell oder Pipeline)
  6. OS-Installation (Ubuntu 24.04 LTS)
  7. cloud-init: Node-Identity schreiben + install.sh ausführen

Phase 2: Ansible (IAC-Ansible)
──────────────────────────────
  8. install.sh installiert Ansible + systemd-Timer
  9. Erster ansible-pull: klont IAC-Ansible, führt site.yml aus
  10. node-identity Rolle: Tags → Gruppen → Rollen
  11. Rollen-spezifische Konfiguration (K8s, Monitoring, etc.)
  12. systemd-Timer: ansible-pull alle 30 Min (Drift-Correction)

Phase 3: Betrieb
────────────────
  13. Push-basiertes Ansible für Ad-hoc Änderungen
  14. MAAS Dynamic Inventory für Ansible Push
  15. Hardware stirbt → MAAS Re-Deploy → Ansible Pull → fertig
```

---

## 2. Voraussetzungen

### 2.1 MAAS Server

| Ressource | Minimum | Empfohlen |
|-----------|---------|-----------|
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Disk | 40 GB | 80 GB+ |
| OS | Ubuntu 22.04 | Ubuntu 24.04 |
| Netzwerk | 1 GbE | 2x 1 GbE |

### 2.2 Managed Nodes

- PXE Boot im BIOS/UEFI aktiviert (erste Boot-Option)
- BMC/IPMI konfiguriert (eigenes Netzwerk)
- Mindestens 1 NIC im PROVISION VLAN

### 2.3 Checkliste vor Start

```
□ config.env an eigene Umgebung angepasst
□ GitHub SSH Deploy Key für IAC-Ansible erstellt
□ IPMI Credentials für jede Maschine dokumentiert
□ VLAN IDs mit Netzwerk-Team abgestimmt
□ IP-Bereiche für DHCP definiert
□ DNS/NTP Server Adressen
□ Switch VLAN-Konfiguration vorbereitet (siehe network/NETWORK-SEGMENTATION.md)
```

---

## 3. Netzwerk-Setup

### 3.1 VLAN-Plan

| VLAN | Subnet | Zweck | DHCP |
|------|--------|-------|------|
| 100 PROVISION | 10.100.0.0/16 | PXE, Commissioning | JA (nur MAAS) |
| 110 MGMT | 10.110.0.0/16 | SSH, Ansible, API | NEIN |
| 120 BMC | 10.120.0.0/16 | IPMI/Redfish | NEIN (statisch) |
| 130 STORAGE | 10.130.0.0/16 | Ceph/NFS (optional) | NEIN |

**Kritisch:** Kein zweiter DHCP-Server im PROVISION VLAN.

Für herstellerunabhängige VLAN-Konfiguration siehe `network/NETWORK-SEGMENTATION.md`.

### 3.2 MAAS Server Netplan

```yaml
# /etc/netplan/01-maas.yaml auf dem MAAS Server
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
  vlans:
    eth0.100:
      id: 100
      link: eth0
      addresses: [10.100.0.1/16]
    eth0.110:
      id: 110
      link: eth0
      addresses: [10.110.0.1/16]
    eth0.120:
      id: 120
      link: eth0
      addresses: [10.120.0.1/16]
```

---

## 4. MAAS Installation

```bash
cd IAC-MAAS

# Zuerst config.env anpassen!
vim config.env

sudo bash maas/scripts/bootstrap-maas.sh
```

Das Script:
1. Installiert MAAS via Snap
2. Initialisiert Region+Rack Controller
3. Erstellt Admin-User (Passwort wird abgefragt)
4. Speichert API-Key
5. Setzt DNS, NTP, Default OS
6. Importiert Ubuntu Images

### 4.1 Nach dem Bootstrap

```bash
# Netzwerk konfigurieren
bash maas/scripts/configure-network.sh

# Images prüfen (dauert 10-30 Min)
bash maas/scripts/import-images.sh

# Web UI öffnen
echo "http://$(hostname -I | awk '{print $1}'):5240/MAAS/"
```

---

## 5. Hardware registrieren

### 5.1 Automatisch (PXE Discovery)

Hardware einfach einschalten. Wenn PXE im PROVISION VLAN aktiv:
- MAAS erkennt die Maschine automatisch
- Commissioning startet
- Status wechselt zu "New" → "Commissioning" → "Ready"

### 5.2 Manuell (IPMI bekannt)

```bash
bash maas/scripts/register-machine.sh \
  --hostname node-01 \
  --bmc-ip 10.120.0.101 \
  --bmc-user admin \
  --bmc-pass 'password' \
  --tags k8s-worker,ssd
```

### 5.3 Tags setzen

Tags bestimmen, welche Ansible-Rolle der Node bekommt:

| Tag | Ansible-Gruppe | Rolle |
|-----|---------------|-------|
| `k8s-control` | `tag_k8s_control` | Kubernetes Control Plane |
| `k8s-worker` | `tag_k8s_worker` | Kubernetes Worker |
| `monitoring` | `tag_monitoring` | Prometheus/Grafana Stack |
| `storage` | `tag_storage` | Ceph/Longhorn |
| `docker` | `tag_docker` | Docker Standalone |
| `gpu` | `tag_gpu` | GPU Workloads |

---

## 6. Deployment

### 6.1 Einzelne Maschine

```bash
# Default: Ubuntu 24.04 (noble)
bash maas/scripts/deploy-machine.sh <SYSTEM_ID>

# Spezifisches Release
bash maas/scripts/deploy-machine.sh <SYSTEM_ID> noble
```

### 6.2 Bulk-Deployment (nach Tag)

```bash
# Alle Ready-Maschinen mit Tag k8s-worker deployen
source maas/scripts/api-helpers.sh
maas_bulk_deploy k8s-worker noble
```

### 6.3 Was passiert beim Deploy

```
MAAS Deploy-Befehl
    │
    ├── 1. OS Image (Ubuntu 24.04) auf Disk streamen
    ├── 2. Bootloader installieren
    ├── 3. cloud-init injizieren:
    │       └── /etc/bauer-group/node-identity.json  (Wer bin ich? MAAS-Tags?)
    │
    ├── 4. Erster Boot
    │       ├── cloud-init: Schreibt Node-Identity
    │       └── cloud-init: Führt IAC-Ansible install.sh aus
    │           ├── Installiert Ansible
    │           ├── Richtet systemd-Timer ein (alle 30 Min)
    │           └── Führt ersten ansible-pull aus (blockierend)
    │
    └── 5. Maschine ist betriebsbereit
```

---

## 7. IAC-Ansible Ergänzungen

### 7.1 Was muss im IAC-Ansible Repo ergänzt werden

Die Dateien in `ansible-additions/` werden in das IAC-Ansible Repo kopiert.
Siehe `ansible-additions/INTEGRATION.md` für die vollständige Anleitung.

### 7.2 Integration testen

```bash
# Push-Test (vom Ansible Controller):
cd IAC-Ansible
ansible-playbook -i inventory/maas/maas_inventory.py site.yml -l tag_k8s_worker

# Pull-Test (auf einem MAAS-deployed Node):
sudo ansible-pull --url https://github.com/bauer-group/IAC-Ansible.git site.yml
```

---

## 8. Betrieb

### 8.1 Neue Hardware hinzufügen

```bash
# 1. Physisch installieren, BMC konfigurieren
# 2. Registrieren
bash maas/scripts/register-machine.sh --hostname node-05 --bmc-ip 10.120.0.105 ...
# 3. Warten auf Commissioning (automatisch)
# 4. Tag setzen
maas admin tag update-nodes k8s-worker add=<SYSTEM_ID>
# 5. Deployen
bash maas/scripts/deploy-machine.sh <SYSTEM_ID>
# 6. install.sh + Ansible laufen automatisch via cloud-init
```

### 8.2 Maschine neu provisionieren

```bash
maas admin machine release <SYSTEM_ID>   # OS löschen
# Warten bis Status "Ready"
bash maas/scripts/deploy-machine.sh <SYSTEM_ID>
```

### 8.3 Ad-hoc Ansible (Push)

```bash
cd IAC-Ansible
# Alle deployed Nodes
ansible-playbook -i inventory/maas/maas_inventory.py playbooks/update-packages.yml

# Nur bestimmte Gruppe
ansible -i inventory/maas/maas_inventory.py tag_k8s_worker -m shell -a "uptime"
```

### 8.4 Drift Correction

Der systemd-Timer `ansible-pull` alle 30 Minuten stellt sicher:
- Konfigurationsänderungen in Git werden automatisch übernommen
- Manuell geänderte Configs werden zurückgesetzt
- Neue Rollen/Tasks werden automatisch angewendet

---

## 9. Troubleshooting

| Problem | Prüfung |
|---------|---------|
| PXE Boot fehl | `tcpdump -i eth0.100 port 67` auf MAAS Server |
| Commissioning hängt | `maas admin node-script-results read <SID>` |
| Deploy fehlgeschlagen | `maas admin machine read <SID> \| jq .error_description` |
| cloud-init Fehler | `ssh ubuntu@<IP> 'cat /var/log/cloud-init-output.log'` |
| ansible-pull Fehler | `ssh ubuntu@<IP> 'journalctl -u ansible-pull'` |
| Node bekommt falsche Rolle | `ssh ubuntu@<IP> 'cat /etc/bauer-group/node-identity.json'` |
| IPMI nicht erreichbar | `ipmitool -I lanplus -H <BMC_IP> -U admin -P pass chassis status` |
| Bootstrap nicht gelaufen | `ssh ubuntu@<IP> 'cat /etc/iac-ansible-bootstrapped'` |

---

## 10. Wichtige Befehle (Referenz)

```bash
# === MAAS ===
maas admin machines read | jq '.[] | {hostname, system_id, status_name, tag_names}'
maas admin machine deploy <SID> distro_series=noble
maas admin machine release <SID>
maas admin machine commission <SID>
maas admin tag update-nodes <TAG> add=<SID>

# === Ansible (Push) ===
ansible-playbook -i inventory/maas/maas_inventory.py site.yml
ansible-playbook -i inventory/maas/maas_inventory.py site.yml -l tag_monitoring
ansible -i inventory/maas/maas_inventory.py all -m ping

# === Ansible (Pull, auf Node) ===
sudo systemctl status ansible-pull.timer     # Timer Status
sudo journalctl -u ansible-pull              # Log prüfen
cat /etc/bauer-group/node-identity.json       # Identity prüfen
cat /etc/iac-ansible-bootstrapped            # Bootstrap-Marker
```
