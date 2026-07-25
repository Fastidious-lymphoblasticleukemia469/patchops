#!/usr/bin/env python3
"""Extract CVE IDs from each security package's changelog.

apt-get changelog fetches the real Debian/Ubuntu changelog for the package,
which lists the CVE(s) each security update fixes. This is the actual source
of truth for "which CVEs does this update fix" — far more precise than
guessing from the package name alone. Best-effort: a package whose changelog
can't be fetched just gets an empty CVE list, it doesn't fail the scan.

Usage: extract_cves.py <path to a JSON file containing an array of package_details>
Prints the same array back with a "cve_ids" key added to each entry.

Takes a file path rather than the JSON itself as an argument — passing the
payload inline risks exceeding the kernel's per-argument length limit
(MAX_ARG_STRLEN, ~128KiB) on a fleet with enough hosts/packages.
"""
import sys
import json
import re
import subprocess

CVE_PATTERN = re.compile(r'CVE-\d{4}-\d{4,}')
ENTRY_PATTERN = re.compile(r'^\S+\s+\(([^)]+)\)\s')


def is_newer(v1, v2):
    if not v2:
        return True
    try:
        subprocess.run(['dpkg', '--compare-versions', v1, 'gt', v2], check=True)
        return True
    except Exception:
        return False


def main():
    with open(sys.argv[1]) as f:
        packages = json.load(f)

    for pkg in packages:
        pkg['cve_ids'] = []
        if not pkg.get('is_security'):
            continue
        try:
            proc = subprocess.run(
                ['apt-get', 'changelog', pkg['package_name']],
                capture_output=True, text=True, timeout=20,
            )
            text = proc.stdout
        except Exception:
            continue
        if not text:
            continue
        cves = set()
        current = pkg.get('current_version', '')
        in_relevant_entry = True
        for line in text.splitlines():
            m = ENTRY_PATTERN.match(line)
            if m:
                in_relevant_entry = is_newer(m.group(1), current)
                if not in_relevant_entry:
                    break
            if in_relevant_entry:
                cves.update(CVE_PATTERN.findall(line))
        pkg['cve_ids'] = sorted(cves)[:5]

    print(json.dumps(packages))


if __name__ == '__main__':
    main()
