CREATE TABLE IF NOT EXISTS patch_history (
  id SERIAL PRIMARY KEY,
  hostname TEXT NOT NULL,
  env_name TEXT NOT NULL,
  patch_timestamp TIMESTAMPTZ NOT NULL,
  patch_type TEXT,
  snapshot_used TEXT,
  packages_changed INTEGER,
  awx_job_id TEXT,
  operator TEXT,
  status TEXT,
  reboot_done BOOLEAN DEFAULT false,
  packages_detail JSONB
);

CREATE INDEX IF NOT EXISTS idx_patch_hostname
  ON patch_history (hostname, patch_timestamp DESC);
