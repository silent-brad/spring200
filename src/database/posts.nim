import db_connector/db_sqlite
import strutils
import times
import ../types

proc create_post*(db: DbConn, walker_id: int64, text_content: string,
    image_filename: string = ""): int64 =
  db.insert_id(sql"INSERT INTO post (walker_id, text_content, image_filename) VALUES (?, ?, ?)",
              walker_id, text_content, image_filename)

proc get_all_posts*(db: DbConn): seq[Post] =
  let rows = db.get_all_rows(sql"""
    SELECT p.id, p.walker_id, u.name, u.avatar_filename, p.text_content, p.image_filename, p.created_at
    FROM post p
    JOIN walker u ON p.walker_id = u.id
    ORDER BY p.created_at DESC
  """)

  var posts: seq[Post] = @[]
  for row in rows:
    posts.add(Post(
      id: parse_biggest_int(row[0]),
      walker_id: parse_biggest_int(row[1]),
      name: row[2],
      avatar_filename: row[3],
      text_content: row[4],
      image_filename: row[5],
      created_at: parse(row[6], "yyyy-MM-dd HH:mm:ss")
    ))

  return posts

proc get_posts_paginated*(db: DbConn, limit: int, offset: int): seq[Post] =
  let rows = db.get_all_rows(sql"""
    SELECT p.id, p.walker_id, u.name, u.avatar_filename, p.text_content, p.image_filename, p.created_at
    FROM post p
    JOIN walker u ON p.walker_id = u.id
    ORDER BY p.created_at DESC
    LIMIT ? OFFSET ?
  """, limit, offset)

  var posts: seq[Post] = @[]
  for row in rows:
    posts.add(Post(
      id: parse_biggest_int(row[0]),
      walker_id: parse_biggest_int(row[1]),
      name: row[2],
      avatar_filename: row[3],
      text_content: row[4],
      image_filename: row[5],
      created_at: parse(row[6], "yyyy-MM-dd HH:mm:ss")
    ))

  return posts

proc get_post_count*(db: DbConn): int64 =
  let row = db.get_row(sql"SELECT COUNT(*) FROM post")
  return parse_biggest_int(row[0])

proc get_post_by_id*(db: DbConn, post_id: int64): Post =
  let row = db.get_row(sql"""
    SELECT p.id, p.walker_id, u.name, u.avatar_filename, p.text_content, p.image_filename, p.created_at
    FROM post p
    JOIN walker u ON p.walker_id = u.id
    WHERE p.id = ?
  """, post_id)

  return Post(
    id: parse_biggest_int(row[0]),
    walker_id: parse_biggest_int(row[1]),
    name: row[2],
    avatar_filename: row[3],
    text_content: row[4],
    image_filename: row[5],
    created_at: parse(row[6], "yyyy-MM-dd HH:mm:ss")
  )

proc update_post*(db: DbConn, post_id: int64, text_content: string,
    image_filename: string) =
  db.exec(sql"UPDATE post SET text_content = ?, image_filename = ? WHERE id = ?",
          text_content, image_filename, post_id)

proc delete_post*(db: DbConn, post_id: int64) =
  db.exec(sql"DELETE FROM post WHERE id = ?", post_id)
