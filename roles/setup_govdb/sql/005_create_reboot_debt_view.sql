CREATE OR REPLACE VIEW reboot_debt AS
  SELECT
      ph.hostname,
      ph.env_name,
      ph.patch_timestamp AS kernel_patched_at,
      EXTRACT(DAY FROM NOW() - ph.patch_timestamp)::INTEGER AS days_overdue,
      sr.reboot_required
  FROM patch_history ph
  JOIN scan_results sr ON sr.hostname = ph.hostname
  WHERE ph.patch_type = 'kernel'
    AND ph.reboot_done = false
    AND sr.reboot_required = true
    AND sr.scan_timestamp = (
        SELECT MAX(scan_timestamp)
        FROM scan_results
        WHERE hostname = ph.hostname
    );
