import db_connector/db_sqlite
import strutils
import times
import ../types

proc create_post*(db: DbConn, walker_id: int64, text_content: string,
    image_filename: string = ""): int64 =
  db.insertID(sql"INSERT INTO post (walker_id, text_content, image_filename) VALUES (?, ?, ?)",
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
