#!/usr/bin/env python3
"""Flatten per-host package details into DB-ready rows, enriched with CVE info.

Picking the "worst" (highest-scored) CVE per package out of a list is easier
here than as nested Jinja lookups across two dicts.

Usage: enrich_package_rows.py <path to a JSON file containing {"hosts": [...], "cve_info": {...}}>
Prints a JSON array of flattened row dicts ready for governance DB insertion.

Takes a file path rather than the JSON itself as an argument — passing the
payload inline risks exceeding the kernel's per-argument length limit
(MAX_ARG_STRLEN, ~128KiB) on a fleet with enough hosts/packages.
"""
import sys
import json


def main():
    with open(sys.argv[1]) as f:
        payload = json.load(f)
    hosts = payload['hosts']
    cve_info = payload['cve_info']

    rows = []
    for h in hosts:
        for pkg in h.get('package_details', []):
            cve_ids = pkg.get('cve_ids') or []
            best_id, best_score, best_priority = None, None, None
            for cid in cve_ids:
                info = cve_info.get(cid, {})
                score = info.get('score')
                if score is not None and (best_score is None or score > best_score):
                    best_id, best_score, best_priority = cid, score, info.get('priority')
            if best_id is None and cve_ids:
                best_id = cve_ids[0]
            rows.append({
                'hostname': h['hostname'],
                'env_name': h['env_name'],
                'package_name': pkg['package_name'],
                'current_version': pkg.get('current_version') or '',
                'new_version': pkg.get('new_version') or '',
                'is_security': bool(pkg.get('is_security', False)),
                'tier_label': 'SECURITY' if pkg.get('is_security') else 'MAINT',
                'cve_id': ', '.join(cve_ids) if cve_ids else None,
                'cve_priority': best_priority,
                'cvss_score': best_score,
            })
    print(json.dumps(rows))


if __name__ == '__main__':
    main()
