import db_connector/db_sqlite
import strutils
from times import DateTime, parse
import models

proc log_miles*(db: DbConn, walker_id: int64, miles: float) =
  db.exec(sql"INSERT INTO mile_entry (walker_id, miles) VALUES (?, ?)",
      walker_id, miles)

proc get_user_total_miles*(db: DbConn, walker_id: int64): float =
  let row = db.get_row(sql"SELECT COALESCE(SUM(miles), 0) FROM mile_entry WHERE walker_id = ?", walker_id)
  return parse_float(row[0])

proc get_user_miles_by_date*(db: DbConn, walker_id: int64): seq[tuple[
    date: string, miles: float]] =
  let rows = db.get_all_rows(sql"""
    SELECT DATE(logged_at) as date, SUM(miles) as daily_miles
    FROM mile_entry
    WHERE walker_id = ?
    GROUP BY DATE(logged_at)
    ORDER BY date ASC
  """, walker_id)

  var results: seq[tuple[date: string, miles: float]] = @[]
  for row in rows:
    results.add((row[0], parse_float(row[1])))

  return results

proc get_user_recent_entries*(db: DbConn, walker_id: int64,
    limit: int = 10, offset: int = 0): seq[MileEntry] =
  let rows = db.get_all_rows(sql"""
    SELECT id, walker_id, miles, logged_at
    FROM mile_entry
    WHERE walker_id = ?
    ORDER BY logged_at DESC
    LIMIT ? OFFSET ?
  """, walker_id, limit, offset)

  var results: seq[MileEntry] = @[]
  for row in rows:
    results.add(MileEntry(
      id: parse_biggest_int(row[0]),
      walker_id: parse_biggest_int(row[1]),
      miles: parse_float(row[2]),
      logged_at: parse(row[3], "yyyy-MM-dd HH:mm:ss")
    ))

  return results

proc get_user_entry_count*(db: DbConn, walker_id: int64): int =
  let row = db.get_row(sql"SELECT COUNT(*) FROM mile_entry WHERE walker_id = ?", walker_id)
  return parse_int(row[0])

proc get_mile_entry_by_id*(db: DbConn, entry_id: int64): MileEntry =
  let row = db.get_row(sql"SELECT id, walker_id, miles, logged_at FROM mile_entry WHERE id = ?", entry_id)
  return MileEntry(
    id: parse_biggest_int(row[0]),
    walker_id: parse_biggest_int(row[1]),
    miles: parse_float(row[2]),
    logged_at: parse(row[3], "yyyy-MM-dd HH:mm:ss")
  )

proc update_mile_entry*(db: DbConn, entry_id: int64, miles: float) =
  db.exec(sql"UPDATE mile_entry SET miles = ? WHERE id = ?", miles, entry_id)

proc delete_mile_entry*(db: DbConn, entry_id: int64) =
  db.exec(sql"DELETE FROM mile_entry WHERE id = ?", entry_id)

proc get_leaderboard_paginated*(db: DbConn, limit: int, offset: int): seq[
    tuple[walker: Walker, total_miles: float]] =
  let rows = db.get_all_rows(sql"""
    SELECT r.id, r.name, r.created_at, r.family_id, r.has_custom_avatar, r.avatar_filename, COALESCE(SUM(m.miles), 0) as total_miles
    FROM walker r
    LEFT JOIN mile_entry m ON r.id = m.walker_id
    GROUP BY r.id
    ORDER BY total_miles DESC
    LIMIT ? OFFSET ?
  """, limit, offset)

  var leaderboard: seq[tuple[walker: Walker, total_miles: float]] = @[]

  for row in rows:
    let walker = Walker(
      id: parse_biggest_int(row[0]),
      name: row[1],
      created_at: row[2].parse("yyyy-MM-dd HH:mm:ss"),
      family_id: parse_biggest_int(row[3]),
      has_custom_avatar: row[4] == "1",
      avatar_filename: row[5]
    )
    let total_miles = parse_float(row[6])

    leaderboard.add((walker, total_miles))

  return leaderboard

proc get_leaderboard*(db: DbConn): seq[tuple[walker: Walker,
    total_miles: float]] =
  let rows = db.get_all_rows(sql"""
    SELECT r.id, r.name, r.created_at, r.family_id, r.has_custom_avatar, r.avatar_filename, COALESCE(SUM(m.miles), 0) as total_miles
    FROM walker r
    LEFT JOIN mile_entry m ON r.id = m.walker_id
    GROUP BY r.id
    ORDER BY total_miles DESC
  """)

  var leaderboard: seq[tuple[walker: Walker, total_miles: float]] = @[]

  for row in rows:
    let walker = Walker(
      id: parse_biggest_int(row[0]),
      name: row[1],
      created_at: row[2].parse("yyyy-MM-dd HH:mm:ss"),
      family_id: parse_biggest_int(row[3]),
      has_custom_avatar: row[4] == "1",
      avatar_filename: row[5]
    )
    let total_miles = parse_float(row[6])

    leaderboard.add((walker, total_miles))

  return leaderboard
