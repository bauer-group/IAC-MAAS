"""
BAUER GROUP – Custom Jinja2 Filter für Ansible.
Verwendung in Templates: {{ maas_tags | bauer_has_tag('k8s-worker') }}
"""


def bauer_has_tag(tags, tag_name):
    """Prüfe ob ein Tag in der Komma-getrennten Tag-Liste enthalten ist."""
    if isinstance(tags, list):
        return tag_name in tags
    if isinstance(tags, str):
        return tag_name in [t.strip() for t in tags.split(',')]
    return False


def bauer_tags_to_list(tags):
    """Konvertiere komma-getrennte Tags in eine Liste."""
    if isinstance(tags, list):
        return tags
    if isinstance(tags, str):
        return [t.strip() for t in tags.split(',') if t.strip()]
    return []


def bauer_memory_gb(memory_mb):
    """Konvertiere MB in GB (aus MAAS Inventory)."""
    try:
        return round(int(memory_mb) / 1024, 1)
    except (ValueError, TypeError):
        return 0


class FilterModule:
    def filters(self):
        return {
            'bauer_has_tag': bauer_has_tag,
            'bauer_tags_to_list': bauer_tags_to_list,
            'bauer_memory_gb': bauer_memory_gb,
        }
