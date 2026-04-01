import db_connector/db_sqlite
import strutils, options, httpclient
from times import DateTime, parse
import os
import ../upload
import models

proc get_walker_by_id*(db: DbConn, walker_id: int64): Option[Walker] =
  let row = db.get_row(sql"SELECT id, family_id, name, has_custom_avatar, avatar_filename, created_at FROM walker WHERE id = ?", walker_id)
  if row[0] == "":
    return none(Walker)

  return some(Walker(
    id: parse_biggest_int(row[0]),
    family_id: parse_biggest_int(row[1]),
    name: row[2],
    has_custom_avatar: row[3] == "1",
    avatar_filename: row[4],
    created_at: parse(row[5], "yyyy-MM-dd HH:mm:ss")
  ))

proc get_walkers_by_family*(db: DbConn, family_id: int64): seq[Walker] =
  let rows = db.get_all_rows(sql"SELECT id, family_id, name, has_custom_avatar, avatar_filename, created_at FROM walker WHERE family_id = ? ORDER BY created_at ASC", family_id)

  var walkers: seq[Walker] = @[]
  for row in rows:
    walkers.add(Walker(
      id: parse_biggest_int(row[0]),
      family_id: parse_biggest_int(row[1]),
      name: row[2],
      has_custom_avatar: row[3] == "1",
      avatar_filename: row[4],
      created_at: parse(row[5], "yyyy-MM-dd HH:mm:ss")
    ))

  return walkers

proc create_generic_avatar(name: string): string =
  # Download and upload avatar
  let avatar_url = "https://ui-avatars.com/api/?background=random&name=" &
      name.replace(" ", "%20") & "&format=webp"
  let client = new_http_client()
  var avatar_filename: string
  try:
    let avatar_data = client.get_content(avatar_url)
    avatar_filename = avatar_data.save_uploaded_file("webp", "avatars")
  finally:
    client.close()
  return avatar_filename

proc create_walker_account*(db: DbConn, family_id: int64, name: string): (int64, string) =
  let avatar_filename = create_generic_avatar(name)
  let walker_id = db.insertID(sql"INSERT INTO walker (family_id, name, has_custom_avatar, avatar_filename) VALUES (?, ?, ?, ?)",
                              family_id, name, false, avatar_filename)
  return (walker_id, avatar_filename)

proc update_walker_name*(db: DbConn, walker_id: int64, name: string) =
  let walker_opt = db.get_walker_by_id(walker_id)
  if walker_opt.is_some:
    # Update the name
    db.exec(sql"UPDATE walker SET name = ? WHERE id = ?", name, walker_id)

    let walker = walker_opt.get()
    if not walker.has_custom_avatar:
      let old_avatar_filename = walker.avatar_filename
      let new_avatar_filename = create_generic_avatar(name)
      db.exec(sql"UPDATE walker SET avatar_filename = ? WHERE id = ?",
          new_avatar_filename, walker_id)
      # Delete the old avatar file
      remove_file("avatars/" & old_avatar_filename)

proc update_walker_avatar*(db: DbConn, avatar_filename: string,
    walker_id: int64) =
  db.exec(sql"UPDATE walker SET has_custom_avatar = true, avatar_filename = ? WHERE id = ?",
      avatar_filename, walker_id)

proc delete_walker_account*(db: DbConn, walker_id: int64) =
  # Get walker info before deletion to access file info
  let walker_opt = get_walker_by_id(db, walker_id)
  if walker_opt.is_some:
    let walker = walker_opt.get()

    # Delete avatar file if it exists
    if walker.avatar_filename.len > 0:
      let avatar_path = "avatars" / walker.avatar_filename
      if file_exists(avatar_path):
        try:
          remove_file(avatar_path)
        except Exception as e:
          echo "Warning: Failed to delete avatar file: ", avatar_path, " - ", e.msg

    # Get all posts by this walker to delete associated picture files
    let post_rows = db.get_all_rows(sql"SELECT image_filename FROM post WHERE walker_id = ? AND image_filename IS NOT NULL AND image_filename != ''", walker_id)
    for row in post_rows:
      if row[0].len > 0:
        let picture_path = "pictures" / row[0]
        if file_exists(picture_path):
          try:
            remove_file(picture_path)
          except Exception as e:
            echo "Warning: Failed to delete picture file: ", picture_path,
                " - ", e.msg

  # Delete associated mile entries and posts first
  db.exec(sql"DELETE FROM mile_entry WHERE walker_id = ?", walker_id)
  db.exec(sql"DELETE FROM post WHERE walker_id = ?", walker_id)

  # Delete the walker account
  db.exec(sql"DELETE FROM walker WHERE id = ?", walker_id)
