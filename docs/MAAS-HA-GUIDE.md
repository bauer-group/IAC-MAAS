# MAAS High Availability Guide

> Architektur und Planung für ein hochverfügbares MAAS-Setup.
> Dieses Dokument ist eine Planungsreferenz — die Umsetzung erfolgt bei Bedarf.

---

## 1. Wann braucht man HA?

| Kriterium | Single-Node reicht | HA empfohlen |
|-----------|-------------------|--------------|
| Managed Nodes | < 50 | 50+ |
| Physische Racks | 1 | 2+ |
| Ausfalltoleranz | Stunden akzeptabel | Minuten/Sekunden |
| Deploy-Frequenz | Gelegentlich | Täglich / CI-getrieben |
| Compliance | Intern | SOC2 / ISO27001 |

**Faustregel:** Wenn ein MAAS-Ausfall Deployments blockiert und das geschäftskritisch ist → HA.

---

## 2. Architektur

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENTS                                      │
│          (Terraform, CLI, Web UI, Ansible Inventory)                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                    ┌────▼─────┐
                    │   VIP    │  10.110.0.10 (keepalived / HAProxy)
                    └────┬─────┘
              ┌──────────┴──────────┐
              │                     │
     ┌────────▼────────┐  ┌────────▼────────┐
     │  maas-region-01  │  │  maas-region-02  │
     │  Region + Rack   │  │  Region + Rack   │
     │  10.110.0.11     │  │  10.110.0.12     │
     └────────┬────────┘  └────────┬─────────┘
              └──────────┬─────────┘
                         │
              ┌──────────▼──────────┐
              │   PostgreSQL HA      │
              │   Primary: 10.110.0.20  │
              │   Standby: 10.110.0.21  │
              │   (repmgr / Patroni)    │
              └─────────────────────┘
```

### Kernprinzip

MAAS unterstützt **nativ** mehrere Region Controller, die sich eine PostgreSQL-Datenbank teilen. Beide sind aktiv — kein Active/Passive.

---

## 3. Komponenten

### 3.1 Region Controller (2x)

Beide Region Controller sind gleichwertig und können:
- API-Anfragen bedienen
- Web UI ausliefern
- Images verwalten
- Deploy-Befehle verarbeiten

**Installation:**
```bash
sudo snap install maas --channel=3.5/stable
sudo maas init region --database-uri "postgres://maas:PASSWORD@10.110.0.20/maasdb"
```

Auf dem zweiten Controller:
```bash
sudo snap install maas --channel=3.5/stable
sudo maas init region --database-uri "postgres://maas:PASSWORD@10.110.0.20/maasdb"
```

### 3.2 Rack Controller (pro Rack)

Pro physischem Rack oder Netzwerksegment ein eigener Rack Controller:
- Lokaler DHCP/TFTP für PXE
- Image-Cache (reduziert WAN-Traffic)
- BMC-Kommunikation

```
Rack A  →  rack-ctrl-a  (DHCP Scope: 10.100.1.0/24)
Rack B  →  rack-ctrl-b  (DHCP Scope: 10.100.2.0/24)
Rack C  →  rack-ctrl-c  (DHCP Scope: 10.100.3.0/24)
```

Rack Controller können auf den Region Controllern laufen (Region+Rack) oder dediziert sein.

**Installation (dediziert):**
```bash
sudo snap install maas --channel=3.5/stable
sudo maas init rack --maas-url http://10.110.0.10:5240/MAAS --secret <SECRET>
```

### 3.3 PostgreSQL HA

MAAS speichert alles in PostgreSQL. Ausfall = kompletter MAAS-Ausfall.

**Option A: repmgr (einfacher)**
- Streaming Replication + automatisches Failover
- Primary + 1 Standby
- `repmgr` monitort und promoted bei Ausfall

**Option B: Patroni (robuster)**
- Patroni + etcd/consul für Leader Election
- Automatisches Failover ohne Split-Brain
- Empfohlen ab 100+ Nodes

**Minimum Setup:**
```
Primary:   10.110.0.20  (PostgreSQL + repmgr)
Standby:   10.110.0.21  (PostgreSQL + repmgr, Streaming Replica)
```

### 3.4 VIP (Virtual IP)

Alle Clients sprechen nur die VIP an — nie direkt die Region Controller.

**keepalived:**
```
VIP: 10.110.0.10
  → Priority 100: maas-region-01 (10.110.0.11)
  → Priority  90: maas-region-02 (10.110.0.12)
```

**Alternativ HAProxy:**
- Load-Balancing über beide Region Controller
- Health-Check: `GET /MAAS/api/2.0/version/`
- Sticky Sessions für Web UI

---

## 4. Hardware-Anforderungen

| Rolle | CPU | RAM | Disk | Netzwerk |
|-------|-----|-----|------|----------|
| Region Controller | 4 vCPU | 8 GB | 50 GB SSD | 2x 1 GbE (bonded) |
| Rack Controller | 2 vCPU | 4 GB | 20 GB | 2x 1 GbE |
| PostgreSQL | 4 vCPU | 16 GB | 100 GB SSD | 1 GbE |

Region und Rack Controller können auf VMs laufen. PostgreSQL sollte auf dedizierter Hardware oder VMs mit garantierten IOPS laufen.

---

## 5. TLS / Reverse Proxy

MAAS liefert HTTP auf Port 5240. Für Produktion:

```
nginx/Caddy → HTTPS (443) → MAAS API (5240)
```

**Warum:**
- API Keys werden im Klartext übertragen ohne TLS
- Terraform/Ansible-Kommunikation sollte verschlüsselt sein
- Compliance-Anforderung

**nginx Beispiel:**
```nginx
upstream maas {
    server 10.110.0.11:5240;
    server 10.110.0.12:5240;
}

server {
    listen 443 ssl;
    server_name maas.cloud.bauer-group.com;

    ssl_certificate     /etc/ssl/maas/cert.pem;
    ssl_certificate_key /etc/ssl/maas/key.pem;

    location / {
        proxy_pass http://maas;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 6. API Key Management

MAAS API Keys haben kein Ablaufdatum. Best Practices:

- **Nie in Git speichern** — Terraform nutzt `TF_VAR_maas_api_key` Environment Variable
- **Vault-Integration** — HashiCorp Vault, AWS Secrets Manager, oder GitHub Secrets
- **Rotation** — Keys regelmässig rotieren, alte widerrufen
- **Least Privilege** — Separate Keys für Terraform (deploy), Ansible (read), Monitoring (read-only)

```bash
# Key erstellen
maas apikey --username terraform-deploy

# Key widerrufen
maas apikey --username terraform-deploy --revoke <KEY>
```

---

## 7. Monitoring

### MAAS Events

MAAS hat einen Event-Stream per API. Ein Exporter kann diese in Prometheus schreiben:
- Failed Commissionings
- Power Failures
- Stuck Deployments
- Controller Health

```bash
# Events abfragen
maas admin events query level=ERROR
```

### Health Checks

| Check | Endpoint / Command | Erwartung |
|-------|-------------------|-----------|
| API erreichbar | `GET /MAAS/api/2.0/version/` | HTTP 200 |
| Region Controller | `maas admin rack-controllers read` | 2 Einträge |
| PostgreSQL | `pg_isready -h 10.110.0.20` | accepting connections |
| DHCP aktiv | `maas admin dhcp-snippets read` | Kein Fehler |
| Images synced | `maas admin boot-resources read` | Status: synced |

---

## 8. Migrations-Checkliste (Single → HA)

```
□ PostgreSQL auf dedizierte Server migrieren
□ Streaming Replication + repmgr/Patroni einrichten
□ Zweiten Region Controller installieren (gleiche DB)
□ keepalived/HAProxy für VIP konfigurieren
□ Alle Clients auf VIP umstellen (config.env, Terraform, Ansible Inventory)
□ TLS Reverse Proxy aufsetzen
□ API Keys rotieren, alte widerrufen
□ Rack Controller pro Rack deployen (falls Multi-Rack)
□ Monitoring für MAAS Controller einrichten
□ Failover-Test: Region-01 herunterfahren, VIP wechselt
□ Failover-Test: PostgreSQL Primary stoppen, Standby promoted
```
