CREATE TABLE IF NOT EXISTS scan_package_details (
  id SERIAL PRIMARY KEY,
  scan_id INTEGER NOT NULL REFERENCES scan_results(id) ON DELETE CASCADE,
  hostname TEXT NOT NULL,
  env_name TEXT NOT NULL,
  scan_timestamp TIMESTAMPTZ NOT NULL,
  package_name TEXT NOT NULL,
  source_package TEXT,
  current_version TEXT,
  new_version TEXT,
  is_security BOOLEAN DEFAULT false,
  tier TEXT,
  tier_label TEXT,
  cve_id TEXT,
  cve_priority TEXT,
  cvss_score REAL
);

CREATE INDEX IF NOT EXISTS idx_pkgdetail_scan
  ON scan_package_details (scan_id);
CREATE INDEX IF NOT EXISTS idx_pkgdetail_hostname
  ON scan_package_details (hostname, scan_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_pkgdetail_env
  ON scan_package_details (env_name, scan_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_pkgdetail_package
  ON scan_package_details (package_name);
