# IAC-Ansible Ergänzungen für MAAS-Integration

> Diese Dateien werden in das bestehende Repository
> `https://github.com/bauer-group/IAC-Ansible` eingepflegt.

## Architektur

```
                    ┌──────────────────────────┐
                    │     IAC-MAAS             │
                    │  (Hardware Provisioning)  │
                    │                          │
                    │  PXE → OS → cloud-init   │
                    └─────────┬────────────────┘
                              │
                              │ cloud-init schreibt:
                              │  /etc/bauer-group/node-identity.json
                              │  + führt install.sh aus
                              │
                    ┌─────────▼────────────────┐
                    │     IAC-Ansible           │
                    │  (Config Management)      │
                    │                          │
                    │  Pull-Modus: site-pull.yml│
                    │  Push-Modus: site.yml     │
                    │                          │
                    │  Rollen:                  │
                    │  ├─ maas-bootstrap        │
                    │  ├─ node-identity         │
                    │  ├─ security-baseline     │
                    │  ├─ monitoring-agent      │
                    │  └─ (eure Rollen...)      │
                    └──────────────────────────┘
```

## Übersicht der neuen Dateien

```
IAC-Ansible/                              (bestehendes Repo)
│
├── site-pull.yml                         ★ Entrypoint für ansible-pull
│
├── inventory/
│   └── maas/
│       ├── maas_inventory.py             ★ MAAS Dynamic Inventory
│       └── maas_inventory.ini            ★ Inventory Konfiguration
│
├── group_vars/
│   ├── all/
│   │   └── maas_integration.yml          ★ Globale MAAS-Variablen
│   ├── tag_k8s_control.yml               ★ K8s Control Plane Vars
│   ├── tag_k8s_worker.yml                ★ K8s Worker Vars
│   ├── tag_monitoring.yml                ★ Monitoring Node Vars
│   ├── tag_storage.yml                   ★ Storage Node Vars
│   └── maas_provisioned.yml              ★ Alle MAAS-deployte Nodes
│
├── roles/
│   ├── maas-bootstrap/                   ★ Erste Rolle nach MAAS
│   ├── node-identity/                    ★ Identity-Loading + Facts
│   ├── security-baseline/                ★ SSH/Firewall/Users/auditd
│   └── monitoring-agent/                 ★ Node Exporter + Promtail
│
├── playbooks/
│   ├── maas-full-provision.yml           ★ Komplette Provisionierung
│   ├── update-packages.yml               ★ Paket-Updates Push-basiert
│   └── reboot-rolling.yml                ★ Rolling Reboot
│
├── callback_plugins/
│   └── maas_report.py                    ★ Callback für MAAS Annotation
│
└── filter_plugins/
    └── bauer_filters.py                  ★ Custom Jinja2 Filter
```

## Wie einfügen

```bash
# Repo klonen
git clone git@github.com:bauer-group/IAC-Ansible.git
cd IAC-Ansible

# Dateien reinkopieren (Verzeichnisstruktur bleibt erhalten)
cp -r /pfad/zu/iac-ansible-additions/* .

# Inventory Script ausführbar machen
chmod +x inventory/maas/maas_inventory.py

# Testen (Pull-Modus lokal)
ansible-playbook site-pull.yml --check -c local -i localhost,

# Testen (Push-Modus mit MAAS Inventory)
ansible-playbook -i inventory/maas/maas_inventory.py site.yml --list-hosts

# Committen
git add -A
git commit -m "feat: MAAS integration - provisioning roles and dynamic inventory"
git push
```

## Zwei Modi

### Pull-Modus (automatisch, durch install.sh gestartet)

cloud-init führt IAC-Ansible `install.sh` aus, das:
1. Ansible installiert (apt)
2. systemd-Timer einrichtet (`ansible-pull.timer`, alle 30 Min)
3. Ersten `ansible-pull` blockierend ausführt

```bash
# Manuell auf einem Node:
sudo systemctl status ansible-pull.timer
sudo journalctl -u ansible-pull
cat /etc/bauer-group/node-identity.json
```

### Push-Modus (manuell, vom Ansible Controller)

Für Ad-hoc Änderungen oder Gruppen-Operationen:
```bash
# Alle MAAS Nodes
ansible-playbook -i inventory/maas/maas_inventory.py site.yml

# Nur K8s Worker
ansible-playbook -i inventory/maas/maas_inventory.py site.yml -l tag_k8s_worker

# Quick Command
ansible -i inventory/maas/maas_inventory.py tag_monitoring -m shell -a "docker ps"
```
