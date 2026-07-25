CREATE TABLE IF NOT EXISTS snapshots (
  name TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  mirror_sources TEXT[],
  dev_published_at TIMESTAMPTZ,
  staging_published_at TIMESTAMPTZ,
  prod_published_at TIMESTAMPTZ,
  approved_by TEXT,
  notes TEXT
);
