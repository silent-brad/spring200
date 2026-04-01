import db_connector/db_sqlite

proc init_database*(): DbConn =
  let db = open("spring92.db", "", "", "")

  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS family (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      created_at DATETIME DEFAULT (DATETIME('now', 'localtime'))
    )
  """)

  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS walker (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      family_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      has_custom_avatar BOOLEAN DEFAULT FALSE,
      avatar_filename TEXT,
      created_at DATETIME DEFAULT (DATETIME('now', 'localtime')),
      FOREIGN KEY (family_id) REFERENCES family (id)
    )
  """)

  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS mile_entry (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      walker_id INTEGER NOT NULL,
      miles REAL NOT NULL,
      logged_at DATETIME DEFAULT (DATETIME('now', 'localtime')),
      FOREIGN KEY (walker_id) REFERENCES walker (id)
    )
  """)

  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS post (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      walker_id INTEGER,
      text_content TEXT NOT NULL,
      image_filename TEXT,
      created_at DATETIME DEFAULT (DATETIME('now', 'localtime')),
      FOREIGN KEY (walker_id) REFERENCES walker (id)
    )
  """)

  return db
