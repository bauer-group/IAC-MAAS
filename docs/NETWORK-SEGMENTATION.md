# Netzwerk-Segmentierung für MAAS

## Übersicht

MAAS benötigt eine saubere Netzwerk-Segmentierung in mindestens drei VLANs.
Die Trennung ist notwendig, damit PXE-Boot-Traffic, Management-Traffic und
IPMI/BMC-Steuerung sich nicht gegenseitig beeinflussen.

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  VLAN 100 – PROVISION            VLAN 110 – MANAGEMENT               │
│  10.100.0.0/16                   10.110.0.0/16                       │
│  PXE, DHCP, TFTP, Images        SSH, Ansible, Monitoring, Internet   │
│                                                                      │
│          │                              │                            │
│          └──────────┐    ┌──────────────┘                            │
│                     ▼    ▼                                           │
│              ┌──────────────────┐                                    │
│              │   MAAS Server    │                                    │
│              │   10.100.0.1     │                                    │
│              │   10.110.0.1     │                                    │
│              └──────────────────┘                                    │
│                     │                                                │
│          ┌──────────┘                                                │
│          ▼                                                           │
│  VLAN 120 – BMC/IPMI                                                 │
│  10.120.0.0/16                                                       │
│  IPMI, iDRAC, iLO (Port 623/UDP)                                    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## VLAN-Definitionen

Alle Werte sind in `config.env` konfigurierbar.
Niedrige VLAN-IDs (1–99) sind für Topologie-VLANs reserviert.

| VLAN | Name | CIDR | Gateway | Zweck |
|------|------|------|---------|-------|
| 100 | PROVISION | 10.100.0.0/16 | 10.100.0.1 | PXE Boot, DHCP, TFTP, Image-Download |
| 110 | MANAGEMENT | 10.110.0.0/16 | 10.110.0.1 | SSH, Ansible, Monitoring, Internet |
| 120 | BMC | 10.120.0.0/16 | — | IPMI/iDRAC/iLO Steuerung |

## DHCP

DHCP wird **ausschließlich** im PROVISION VLAN bereitgestellt — durch MAAS selbst:

| Einstellung | Wert |
|-------------|------|
| Subnet | 10.100.0.0/16 |
| Range | 10.100.1.1 – 10.100.255.250 |
| Gateway | 10.100.0.1 (MAAS Server) |
| DNS | 10.110.0.1 (MAAS DNS) |
| Boot | PXE via MAAS |

MANAGEMENT und BMC VLANs verwenden statische IPs oder externe DHCP-Quellen.

## Firewall-Regeln

### Erlaubter Traffic

| Quelle | Ziel | Protokoll | Port(s) | Beschreibung |
|--------|------|-----------|---------|--------------|
| PROVISION (100) | MAAS Server | UDP | 67–69 | DHCP + TFTP (PXE Boot) |
| PROVISION (100) | MAAS Server | TCP | 80, 443, 5248 | Image-Download + MAAS API |
| PROVISION (100) | MGMT (110) | TCP | * | Deployed Nodes → Management |
| MAAS Server | BMC (120) | UDP | 623 | IPMI Power Control |
| MGMT (110) | Internet | TCP/UDP | * | Updates, Ansible Pull, Monitoring |
| MGMT (110) | PROVISION (100) | TCP | 22 | SSH zu deployed Nodes |

### Gesperrter Traffic (Default Deny)

| Regel | Begründung |
|-------|------------|
| BMC → Internet | BMC Controller dürfen nicht ins Internet |
| BMC → PROVISION | BMC hat keinen Grund mit Nodes zu reden |
| PROVISION → Internet | Nodes laden Images nur über MAAS |
| Inter-VLAN (alles andere) | Nur explizit erlaubter Traffic |

## Port-Übersicht

| Port | Protokoll | Dienst | VLAN |
|------|-----------|--------|------|
| 67–68 | UDP | DHCP | PROVISION |
| 69 | UDP | TFTP (PXE) | PROVISION |
| 80 | TCP | HTTP (Images) | PROVISION |
| 443 | TCP | HTTPS | PROVISION / MGMT |
| 623 | UDP | IPMI/RMCP | BMC |
| 5240 | TCP | MAAS Web UI | MGMT |
| 5248 | TCP | MAAS API (intern) | PROVISION |
| 22 | TCP | SSH | MGMT |
| 9100 | TCP | Node Exporter | MGMT |
| 3100 | TCP | Loki (Logs) | MGMT |

## Umsetzung

Die VLAN-Konfiguration ist **herstellerunabhängig**. Die konkrete Implementierung
hängt von der eingesetzten Switch/Router-Hardware ab.

### Anforderungen an den Switch

1. **802.1Q VLAN-Tagging** muss unterstützt werden
2. **Trunk-Port** zum MAAS Server (alle 3 VLANs getaggt)
3. **Access-Ports** für Nodes (PROVISION VLAN untagged)
4. **Dedicated BMC-Ports** (BMC VLAN untagged) — falls BMC separate NICs hat

### MAAS Server Netzwerk-Interface

Der MAAS Server benötigt ein Interface in jedem VLAN. Beispiel mit Netplan:

```yaml
# /etc/netplan/01-maas.yaml
network:
  version: 2
  ethernets:
    ens192:
      dhcp4: false
  vlans:
    vlan100:
      id: 100
      link: ens192
      addresses: [10.100.0.1/16]
    vlan110:
      id: 110
      link: ens192
      addresses: [10.110.0.1/16]
      routes:
        - to: default
          via: 10.110.0.254   # Upstream Gateway
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
    vlan120:
      id: 120
      link: ens192
      addresses: [10.120.0.1/16]
```

### Node Netzwerk-Interface

Nodes haben typischerweise:

| NIC | Funktion | VLAN | Konfiguration |
|-----|----------|------|---------------|
| NIC 1 (onboard) | PXE Boot + OS | PROVISION (100) | Access Port, untagged |
| BMC (iLO/iDRAC) | Power Control | BMC (120) | Access Port, untagged |

Nach dem Deployment weist MAAS dem Node eine IP im MGMT VLAN zu
(konfigurierbar in MAAS Subnet-Settings).

## Troubleshooting

### Node bootet nicht via PXE

```bash
# DHCP-Traffic auf PROVISION VLAN prüfen
tcpdump -i vlan100 port 67 or port 68

# MAAS DHCP Status
maas admin dhcp-snippets read
maas admin rack-controllers read | jq '.[].interfaces'
```

### IPMI nicht erreichbar

```bash
# BMC VLAN Konnektivität prüfen
ping -c1 10.120.0.<BMC_IP>

# IPMI direkt testen
ipmitool -I lanplus -H 10.120.0.<BMC_IP> -U admin -P <pass> chassis status
```

### Node nach Deployment nicht erreichbar via SSH

```bash
# IP im MAAS prüfen
maas admin machine read <SID> | jq '.ip_addresses'

# Firewall-Regeln prüfen: PROVISION→MGMT Routing erlaubt?
# Node muss nach Deploy eine MGMT-IP bekommen
```
