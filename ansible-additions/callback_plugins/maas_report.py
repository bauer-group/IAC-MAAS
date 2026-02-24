"""
Ansible Callback Plugin: maas_report
Annotiert MAAS Maschinen nach einem Ansible Run.
Setzt Tags wie 'ansible-ok' oder 'ansible-failed'.

Aktivierung in ansible.cfg:
  [defaults]
  callback_plugins = callback_plugins
  callbacks_enabled = maas_report

Voraussetzungen:
  - MAAS_API_URL und MAAS_API_KEY als Umgebungsvariablen
  - Ohne diese Variablen ist das Plugin inaktiv (kein Fehler)
"""

from ansible.plugins.callback import CallbackBase
import json
import os
import urllib.request
import urllib.error


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'notification'
    CALLBACK_NAME = 'maas_report'
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        self.api_url = os.environ.get('MAAS_API_URL', '')
        self.api_key = os.environ.get('MAAS_API_KEY', '')
        self.results = {}
        self.host_system_ids = {}
        self._disabled = not bool(self.api_url and self.api_key)

    def _build_auth_header(self):
        """OAuth1 Header für MAAS API."""
        try:
            consumer_key, token_key, token_secret = self.api_key.split(':')
        except ValueError:
            return None
        return (
            f'OAuth oauth_version="1.0", '
            f'oauth_consumer_key="{consumer_key}", '
            f'oauth_token="{token_key}", '
            f'oauth_signature_method="PLAINTEXT", '
            f'oauth_signature="&{token_secret}"'
        )

    def _maas_api_post(self, endpoint, data):
        """POST an MAAS API mit OAuth1."""
        if self._disabled:
            return
        auth = self._build_auth_header()
        if not auth:
            return
        try:
            url = f"{self.api_url.rstrip('/')}{endpoint}"
            req = urllib.request.Request(
                url,
                data=data.encode() if isinstance(data, str) else data,
                headers={'Authorization': auth},
                method='POST'
            )
            urllib.request.urlopen(req, timeout=10)
        except (urllib.error.URLError, OSError) as e:
            self._display.warning(f"MAAS API call failed ({endpoint}): {e}")

    def _ensure_tag(self, tag_name):
        """Tag in MAAS erstellen (idempotent)."""
        self._maas_api_post('/tags/', f'name={tag_name}')

    def _annotate_machine(self, system_id, tag):
        """Tag auf MAAS Maschine setzen."""
        if not system_id:
            return
        self._maas_api_post(
            f'/tags/{tag}/?op=update_nodes',
            f'add={system_id}'
        )

    def v2_runner_on_ok(self, result):
        host = result._host.get_name()
        self.results.setdefault(host, {'ok': 0, 'failed': 0})
        self.results[host]['ok'] += 1

        # system_id aus Facts oder Hostvars extrahieren
        if host not in self.host_system_ids:
            facts = result._result.get('ansible_facts', {})
            if 'maas_system_id' in facts:
                self.host_system_ids[host] = facts['maas_system_id']
            else:
                try:
                    hostvars = result._task._variable_manager.get_vars(
                        host=result._host
                    )
                    sid = hostvars.get('maas_system_id', '')
                    if sid:
                        self.host_system_ids[host] = sid
                except Exception:
                    pass

    def v2_runner_on_failed(self, result, ignore_errors=False):
        host = result._host.get_name()
        self.results.setdefault(host, {'ok': 0, 'failed': 0})
        if not ignore_errors:
            self.results[host]['failed'] += 1

    def v2_playbook_on_stats(self, stats):
        if self._disabled:
            return

        # Tags erstellen (idempotent)
        self._ensure_tag('ansible-ok')
        self._ensure_tag('ansible-failed')

        annotated = 0
        for host, counts in self.results.items():
            system_id = self.host_system_ids.get(host, '')
            if not system_id:
                continue

            if counts['failed'] > 0:
                self._annotate_machine(system_id, 'ansible-failed')
            else:
                self._annotate_machine(system_id, 'ansible-ok')
            annotated += 1

        if annotated:
            self._display.display(
                f"MAAS: {annotated} Maschine(n) annotiert.", color='green'
            )
