CREATE TABLE daily_events (
  day TEXT NOT NULL,
  event TEXT NOT NULL,
  version TEXT NOT NULL,
  os TEXT NOT NULL,
  arch TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0 CHECK (count >= 0),
  PRIMARY KEY (day, event, version, os, arch)
) WITHOUT ROWID;

CREATE TABLE installations (
  installation_hash TEXT PRIMARY KEY,
  first_seen_day TEXT NOT NULL,
  last_seen_day TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE rate_limits (
  subject_hash TEXT NOT NULL,
  bucket INTEGER NOT NULL,
  count INTEGER NOT NULL CHECK (count > 0),
  expires_at INTEGER NOT NULL,
  PRIMARY KEY (subject_hash, bucket)
) WITHOUT ROWID;

CREATE INDEX rate_limits_expiry ON rate_limits (expires_at);
