#!/usr/bin/env python3
"""Parse `apt list --upgradable` lines into structured package records.

Usage: parse_upgrades.py <path to a JSON file containing an array of upgrade lines>
Prints a JSON array of {package_name, new_version, current_version, is_security}.

Takes a file path rather than the JSON itself as an argument — passing the
payload inline risks exceeding the kernel's per-argument length limit
(MAX_ARG_STRLEN, ~128KiB) on a fleet with enough hosts/packages.
"""
import sys
import json
import re


def main():
    with open(sys.argv[1]) as f:
        lines = json.load(f)
    result = []
    for line in lines:
        # Format: pkg/pocket new_version arch [upgradable from: old_version]
        # e.g. 'tar/noble-updates,noble-security 1.35+dfsg-3ubuntu0.3 amd64 [upgradable from: 1.35+dfsg-3build1]'
        m = re.match(r'^(\S+?)/(\S+)\s+(\S+)\s+\S+\s+\[upgradable from:\s+(\S+)\]', line)
        if m:
            result.append({
                'package_name': m.group(1),
                'new_version': m.group(3),
                'current_version': m.group(4),
                'is_security': 'security' in line.lower(),
            })
        else:
            # Fallback: simpler format
            parts = line.split('/')
            if len(parts) >= 2:
                pkg = parts[0]
                rest = parts[1].split()
                result.append({
                    'package_name': pkg,
                    'new_version': rest[1] if len(rest) > 1 else '',
                    'current_version': '',
                    'is_security': 'security' in line.lower(),
                })
    print(json.dumps(result))


if __name__ == '__main__':
    main()
