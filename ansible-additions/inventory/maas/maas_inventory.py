#!/usr/bin/env python3
"""
MAAS Dynamic Inventory für Ansible (Push-Modus).

Liest Maschinen aus der MAAS API und gruppiert sie nach:
  - Status:    maas_deployed, maas_ready, maas_commissioning
  - Tags:      tag_k8s_worker, tag_monitoring, tag_storage, ...
  - Zonen:     zone_<name>
  - Pools:     pool_<name>
  - Meta:      maas_provisioned (alle deployed Nodes)

Konfiguration:
  Option 1: Umgebungsvariablen MAAS_API_URL, MAAS_API_KEY
  Option 2: maas_inventory.ini (gleicher Ordner)

Verwendung:
  ansible-playbook -i inventory/maas/maas_inventory.py site.yml
  ansible -i inventory/maas/maas_inventory.py tag_k8s_worker -m ping

Optionen:
  --list            Vollständiges Inventory (JSON)
  --host <name>     Hostvars für einzelnen Host
  --refresh-cache   Cache ignorieren und neu laden
  --help            Diese Hilfe anzeigen
"""

import json
import os
import sys
import time
import configparser
import urllib.request
import urllib.error

CACHE_TTL = 60  # Sekunden
CACHE_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    '.maas_inventory_cache.json'
)


def load_config():
    """Lade Konfiguration aus INI-Datei oder Umgebungsvariablen."""
    config = {
        'api_url': os.environ.get('MAAS_API_URL', ''),
        'api_key': os.environ.get('MAAS_API_KEY', ''),
        'ssh_user': os.environ.get('MAAS_SSH_USER', 'ubuntu'),
        'address_type': os.environ.get('MAAS_ADDRESS_TYPE', 'ip'),
    }

    ini_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        'maas_inventory.ini'
    )
    if os.path.exists(ini_path):
        cp = configparser.ConfigParser()
        cp.read(ini_path)
        if 'maas' in cp:
            config['api_url'] = cp.get('maas', 'api_url', fallback=config['api_url'])
            config['api_key'] = cp.get('maas', 'api_key', fallback=config['api_key'])
            config['ssh_user'] = cp.get('maas', 'ssh_user', fallback=config['ssh_user'])
            config['address_type'] = cp.get('maas', 'address_type', fallback=config['address_type'])

    if not config['api_url'] or not config['api_key'] or config['api_key'] == 'CHANGE_ME':
        sys.stderr.write("ERROR: MAAS API Credentials nicht konfiguriert.\n\n")
        sys.stderr.write("Troubleshooting:\n")
        sys.stderr.write("  1. Umgebungsvariablen setzen:\n")
        sys.stderr.write("     export MAAS_API_URL='http://<maas-ip>:5240/MAAS/api/2.0/'\n")
        sys.stderr.write("     export MAAS_API_KEY='<consumer>:<token>:<secret>'\n\n")
        sys.stderr.write("  2. Oder maas_inventory.ini bearbeiten:\n")
        sys.stderr.write(f"     {ini_path}\n\n")
        sys.stderr.write("  API Key abrufen:\n")
        sys.stderr.write("     maas apikey --username admin\n")
        sys.stderr.write("     cat /root/.maas/api-key\n")
        sys.exit(1)

    return config


def maas_api_request(config, endpoint, retries=3):
    """MAAS API Anfrage mit OAuth1 und Retry-Logic."""
    url = config['api_url'].rstrip('/') + endpoint

    try:
        consumer_key, token_key, token_secret = config['api_key'].split(':')
    except ValueError:
        sys.stderr.write("ERROR: MAAS API Key hat falsches Format.\n")
        sys.stderr.write("  Erwartet: consumer_key:token_key:token_secret\n")
        sys.exit(1)

    auth_header = (
        f'OAuth oauth_version="1.0", '
        f'oauth_consumer_key="{consumer_key}", '
        f'oauth_token="{token_key}", '
        f'oauth_signature_method="PLAINTEXT", '
        f'oauth_signature="&{token_secret}"'
    )

    req = urllib.request.Request(url, headers={'Authorization': auth_header})

    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            sys.stderr.write(f"ERROR: MAAS API HTTP {e.code}: {e.reason}\n")
            if e.code == 401:
                sys.stderr.write("  API Key ist ungueltig oder abgelaufen.\n")
                sys.exit(1)
            if attempt < retries:
                wait = 2 ** attempt
                sys.stderr.write(f"  Retry {attempt}/{retries} in {wait}s...\n")
                time.sleep(wait)
            else:
                sys.exit(1)
        except urllib.error.URLError as e:
            sys.stderr.write(f"ERROR: MAAS nicht erreichbar: {e.reason}\n")
            sys.stderr.write(f"  URL: {url}\n")
            if attempt < retries:
                wait = 2 ** attempt
                sys.stderr.write(f"  Retry {attempt}/{retries} in {wait}s...\n")
                time.sleep(wait)
            else:
                sys.stderr.write("  Prüfen: MAAS Server läuft? Netzwerk OK? URL korrekt?\n")
                sys.exit(1)

    sys.exit(1)


def load_cache():
    """Lade Inventory aus Cache falls vorhanden und aktuell."""
    if not os.path.exists(CACHE_FILE):
        return None
    try:
        mtime = os.path.getmtime(CACHE_FILE)
        if time.time() - mtime > CACHE_TTL:
            return None
        with open(CACHE_FILE) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def save_cache(inventory):
    """Speichere Inventory in Cache-Datei."""
    try:
        with open(CACHE_FILE, 'w') as f:
            json.dump(inventory, f, indent=2)
    except OSError:
        pass


def build_inventory(config):
    """Baue Ansible Inventory aus MAAS Daten."""
    machines = maas_api_request(config, '/machines/?op=list')

    inventory = {
        '_meta': {'hostvars': {}},
        'all': {'children': ['maas_provisioned']},
        'maas_provisioned': {'hosts': [], 'children': []},
        'maas_deployed': {'hosts': []},
        'maas_ready': {'hosts': []},
        'maas_commissioning': {'hosts': []},
    }

    for m in machines:
        hostname = m.get('hostname', '')
        system_id = m.get('system_id', '')
        status = m.get('status_name', '').lower()
        tags = m.get('tag_names', [])
        ips = m.get('ip_addresses', [])

        # Nur deployed Nodes als erreichbare Hosts
        if status != 'deployed':
            status_group = f'maas_{status.replace(" ", "_")}'
            if status_group not in inventory:
                inventory[status_group] = {'hosts': []}
            inventory[status_group]['hosts'].append(hostname)
            continue

        # IP oder Hostname als Ansible Host
        if config['address_type'] == 'ip' and ips:
            ansible_host = ips[0]
        else:
            ansible_host = hostname

        # Host zu deployed + maas_provisioned
        inventory['maas_deployed']['hosts'].append(hostname)
        inventory['maas_provisioned']['hosts'].append(hostname)

        # Hostvars
        inventory['_meta']['hostvars'][hostname] = {
            'ansible_host': ansible_host,
            'ansible_user': config['ssh_user'],
            'ansible_become': True,
            'maas_system_id': system_id,
            'maas_status': status,
            'maas_tags': tags,
            'maas_ip_addresses': ips,
            'maas_hostname': hostname,
            'maas_fqdn': m.get('fqdn', hostname),
            'maas_zone': m.get('zone', {}).get('name', ''),
            'maas_pool': m.get('pool', {}).get('name', ''),
            'maas_cpu_count': m.get('cpu_count', 0),
            'maas_memory_mb': m.get('memory', 0),
            'maas_architecture': m.get('architecture', ''),
            'maas_osystem': m.get('osystem', ''),
            'maas_distro_series': m.get('distro_series', ''),
            'maas_power_type': m.get('power_type', ''),
        }

        # Tag-basierte Gruppen
        for tag in tags:
            safe_tag = tag.replace('-', '_').replace('.', '_')
            group_name = f'tag_{safe_tag}'
            if group_name not in inventory:
                inventory[group_name] = {'hosts': []}
                inventory['maas_provisioned'].setdefault('children', []).append(group_name)
            inventory[group_name]['hosts'].append(hostname)

        # Zone-basierte Gruppen
        zone = m.get('zone', {}).get('name', '')
        if zone:
            zone_group = f'zone_{zone}'
            if zone_group not in inventory:
                inventory[zone_group] = {'hosts': []}
            inventory[zone_group]['hosts'].append(hostname)

        # Pool-basierte Gruppen
        pool = m.get('pool', {}).get('name', '')
        if pool and pool != 'default':
            pool_group = f'pool_{pool}'
            if pool_group not in inventory:
                inventory[pool_group] = {'hosts': []}
            inventory[pool_group]['hosts'].append(hostname)

    return inventory


def print_help():
    """Hilfe anzeigen."""
    print(__doc__)


def main():
    if '--help' in sys.argv or '-h' in sys.argv:
        print_help()
        sys.exit(0)

    config = load_config()
    refresh = '--refresh-cache' in sys.argv

    if '--host' in sys.argv:
        hostname = sys.argv[sys.argv.index('--host') + 1]
        # Versuche aus Cache
        inventory = None if refresh else load_cache()
        if not inventory:
            inventory = build_inventory(config)
            save_cache(inventory)
        hostvars = inventory.get('_meta', {}).get('hostvars', {}).get(hostname, {})
        print(json.dumps(hostvars, indent=2))
    else:
        inventory = None if refresh else load_cache()
        if not inventory:
            inventory = build_inventory(config)
            save_cache(inventory)
        print(json.dumps(inventory, indent=2))


if __name__ == '__main__':
    main()
