#!/usr/bin/env nu

# Migrate user data from an old Spring92 site to the current one.
# Copies families, walkers, posts, avatars, and post pictures.
# Skips mile_entry so users get a fresh start.
#
# Usage: nu migrate.nu /path/to/old/site

def main [old_site: path] {
  let old_db = ($old_site | path join "winter91.db")
  let new_db = "spring92.db"

  if not ($old_db | path exists) {
    error make { msg: $"Old database not found at ($old_db)" }
  }
  if not ($new_db | path exists) {
    error make { msg: $"New database not found at ($new_db)" }
  }

  # Helper: escape single quotes for SQL string literals
  let esc = {|s| $s | str replace --all "'" "''" }

  # ── Families ──────────────────────────────────────────────
  print "Migrating families..."
  let families = (open $old_db | query db "SELECT id, email, password_hash, created_at FROM family")
  mut family_map: record = {}

  for fam in $families {
    let existing = (open $new_db
      | query db $"SELECT id FROM family WHERE email = '(do $esc $fam.email)'")

    if ($existing | length) > 0 {
      print $"  skip  ($fam.email) \(already exists\)"
      $family_map = ($family_map | insert ($fam.id | into string) $existing.0.id)
    } else {
      let email = (do $esc $fam.email)
      let hash = (do $esc $fam.password_hash)
      let ts   = (do $esc ($fam.created_at | into string))

      sqlite3 $new_db $"INSERT INTO family \(email, password_hash, created_at\) VALUES \('($email)', '($hash)', '($ts)'\)"

      let new_id = (open $new_db | query db "SELECT last_insert_rowid() as id").0.id
      $family_map = ($family_map | insert ($fam.id | into string) $new_id)
      print $"  added ($fam.email)  \(($fam.id) → ($new_id)\)"
    }
  }

  # ── Walkers ───────────────────────────────────────────────
  print "\nMigrating walkers..."
  let walkers = (open $old_db
    | query db "SELECT id, family_id, name, has_custom_avatar, avatar_filename, created_at FROM walker")
  mut walker_map: record = {}

  for w in $walkers {
    let new_family_id = ($family_map | get ($w.family_id | into string))
    let name     = (do $esc $w.name)
    let avatar   = (do $esc ($w.avatar_filename | default "" | into string))
    let has_av   = ($w.has_custom_avatar | default 0)
    let ts       = (do $esc ($w.created_at | into string))

    sqlite3 $new_db $"INSERT INTO walker \(family_id, name, has_custom_avatar, avatar_filename, created_at\) VALUES \(($new_family_id), '($name)', ($has_av), '($avatar)', '($ts)'\)"

    let new_id = (open $new_db | query db "SELECT last_insert_rowid() as id").0.id
    $walker_map = ($walker_map | insert ($w.id | into string) $new_id)
    print $"  added ($w.name)  \(($w.id) → ($new_id)\)"
  }

  # ── Avatar files ──────────────────────────────────────────
  let old_avatars = ($old_site | path join "avatars")
  if ($old_avatars | path exists) {
    print "\nCopying avatars..."
    mkdir avatars
    let files = (ls $old_avatars | where type == file)
    for f in $files {
      let dest = ("avatars" | path join ($f.name | path basename))
      cp $f.name $dest
      print $"  ($f.name | path basename)"
    }
    print $"  ($files | length) avatar\(s\) copied"
  }

  print "\nMigration complete!"
  print $"  Families: ($families | length)"
  print $"  Walkers:  ($walkers | length)"
  print "  Posts:    skipped \(fresh start\)"
  print "  Miles:    skipped \(fresh start\)"
}
