#!/usr/bin/env nu

# Add an index on post.created_at to speed up paginated queries.
#
# Usage: nu sql/add_post_index.nu

def main [] {
  let db = "spring92.db"

  if not ($db | path exists) {
    error make { msg: $"Database not found at ($db)" }
  }

  print "Creating index on post.created_at..."
  sqlite3 $db "CREATE INDEX IF NOT EXISTS idx_post_created_at ON post (created_at DESC)"
  print "  done"

  print "\nMigration complete!"
}
