# MAAS-Integration in IAC-Ansible

## Voraussetzungen

- Bestehendes IAC-Ansible Repository (github.com/bauer-group/IAC-Ansible)
- MAAS Server eingerichtet (siehe IAC-MAAS Repository)
- Python 3.8+ auf dem Ansible Controller

## Integration

```bash
# 1. IAC-Ansible Repo klonen
git clone git@github.com:bauer-group/IAC-Ansible.git
cd IAC-Ansible

# 2. MAAS-Additions kopieren
cp -r /path/to/IAC-MAAS/ansible-additions/* .

# 3. Inventory-Script ausführbar machen
chmod +x inventory/maas/maas_inventory.py

# 4. Konfiguration anpassen
#    - group_vars/all/maas_integration.yml → Monitoring-IPs, Domain, etc.
#    - inventory/maas/maas_inventory.ini   → MAAS API URL + Key

# 5. Commit
git add -A && git commit -m "feat: MAAS integration"
```

## Was wird hinzugefügt

| Pfad | Zweck |
|------|-------|
| `site-pull.yml` | Entrypoint für ansible-pull (MAAS cloud-init → hier) |
| `roles/node-identity/` | Brücke MAAS→Ansible: lädt /etc/bauer-group/node-identity.json |
| `roles/maas-bootstrap/` | Basispakete, NTP, Hostname, Sysctl, MOTD |
| `roles/security-baseline/` | SSH-Hardening, UFW, fail2ban, auditd |
| `roles/monitoring-agent/` | Node Exporter + Promtail auf jedem Node |
| `inventory/maas/` | Dynamic Inventory (MAAS API → Ansible Gruppen) |
| `group_vars/` | Tag-basierte Variablen (K8s, Monitoring, Storage) |
| `callback_plugins/maas_report.py` | Annotiert MAAS-Maschinen nach Ansible Run |
| `filter_plugins/bauer_filters.py` | Jinja2 Filter für Tag-Operationen |
| `playbooks/` | Operational Playbooks (Rolling Reboot, Updates) |

## Dual-Mode: MAAS + Nicht-MAAS

Die Integration ist so designed, dass das Ansible Repo **unabhängig von MAAS** nutzbar bleibt:

- `node-identity` Rolle prüft ob `/etc/bauer-group/node-identity.json` existiert
- Wenn ja → MAAS-Managed: setzt `bauergroup_maas_managed: true`
- Wenn nein → Fallback: setzt `bauergroup_maas_managed: false`
- `maas-bootstrap` läuft nur auf MAAS-Nodes (`when: bauergroup_maas_managed`)
- `security-baseline` und `monitoring-agent` laufen auf allen Nodes

## Dynamic Inventory (Push-Modus)

```bash
# Konfiguration
export MAAS_API_URL='http://10.110.0.1:5240/MAAS/api/2.0/'
export MAAS_API_KEY='consumer:token:secret'

# Alle MAAS-deployed Nodes
ansible-playbook -i inventory/maas/maas_inventory.py site.yml

# Nur K8s Worker
ansible -i inventory/maas/maas_inventory.py tag_k8s_worker -m ping

# Cache erneuern
./inventory/maas/maas_inventory.py --refresh-cache --list
```

## Pull-Modus (automatisch)

Nach MAAS-Deployment führt cloud-init IAC-Ansible `install.sh` aus:

- Installiert Ansible via apt
- Richtet `ansible-pull.timer` (systemd) ein (alle 30 Min)
- Führt ersten `ansible-pull` blockierend aus
- Identity: `/etc/bauer-group/node-identity.json`
