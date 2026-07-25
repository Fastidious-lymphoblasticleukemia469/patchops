CREATE TABLE IF NOT EXISTS scan_results (
  id SERIAL PRIMARY KEY,
  hostname TEXT NOT NULL,
  env_name TEXT NOT NULL,
  scan_timestamp TIMESTAMPTZ NOT NULL,
  risk_tier TEXT,
  risk_score INTEGER,
  cve_count INTEGER,
  max_cvss REAL,
  security_count INTEGER,
  regular_count INTEGER,
  total_upgrades INTEGER,
  reboot_required BOOLEAN,
  reboot_pending_days INTEGER,
  internet_exposed BOOLEAN,
  business_criticality TEXT,
  snapshot_used TEXT,
  awx_job_id TEXT,
  raw_result JSONB
);

CREATE INDEX IF NOT EXISTS idx_scan_hostname
  ON scan_results (hostname, scan_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_scan_env
  ON scan_results (env_name, scan_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_scan_risk
  ON scan_results (risk_tier, scan_timestamp DESC);
