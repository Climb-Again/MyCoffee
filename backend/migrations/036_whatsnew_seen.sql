-- #201 — per-user What's New seen state (phone ↔ iPad sync).
--
-- No user_id column on purpose: MyCoffee has one shared INGEST_TOKEN for all
-- of Radu's devices, so one seen set is exactly right. If a second identity
-- ever exists, this table gains a `token_hash` column and the PK becomes
-- composite -- it's a forward-only migration, not a redesign.
--
-- `entry_key` is a client-generated stable hash of `title\ndetail` (FNV-1a);
-- the server never inspects it, only stores and returns it. The client owns
-- the mapping to a real entry.
CREATE TABLE IF NOT EXISTS whatsnew_seen (
  entry_key TEXT PRIMARY KEY,
  seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
