import asynchttpserver
import options
import os, strutils, macros
import times, strformat
import ../types, ../utils, ../database/models

template guard_walker*(session: Option[Session]): untyped =
  if session.is_none or session.get().is_family_session:
    let loc = if session.is_none: "/login" else: "/select-walker"
    return ("", Http302, new_http_headers([("Location", loc)]))

template guard_login*(session: Option[Session]): untyped =
  if session.is_none:
    return ("", Http302, new_http_headers([("Location", "/login")]))

template guard_json_unauthorized*(session: Option[Session]): untyped =
  if session.is_none or session.get().is_family_session:
    return ("{\"error\": \"Unauthorized\"}", Http401,
            new_http_headers([("Content-Type", "application/json")]))

proc post_unauthorized*(msg: string): (string, HttpCode, HttpHeaders) =
  (html_error(msg), Http401, new_http_headers([("Content-Type", "text/html")]))

proc serve_static_file*(req_path, url_prefix, dir: string,
                        client_headers: HttpHeaders,
                        check_safe_ext: bool = false): (string, HttpCode, HttpHeaders) =
  let file_path = sanitize_path(req_path[url_prefix.len..^1])
  let full_path = dir / file_path

  if file_path.contains("..") or not full_path.starts_with(dir & "/"):
    return ("Access denied", Http403, new_http_headers([("Content-Type", "text/html")]))

  if check_safe_ext and not is_safe_file_extension(file_path):
    return ("File type not allowed", Http403, new_http_headers([("Content-Type", "text/html")]))

  if not file_exists(full_path):
    return ("File not found", Http404, new_http_headers([("Content-Type", "text/html")]))

  let ext = split_file(full_path).ext.to_lower_ascii()
  let content_type = case ext:
    of ".js": "application/javascript"
    of ".css": "text/css"
    of ".html": "text/html"
    of ".png": "image/png"
    of ".webp": "image/webp"
    of ".jpg", ".jpeg": "image/jpeg"
    of ".gif": "image/gif"
    of ".svg": "image/svg+xml"
    of ".ico": "image/x-icon"
    of ".webmanifest": "application/manifest+json"
    else: "application/octet-stream"

  let file_info = get_file_info(full_path)
  let last_modified = file_info.last_write_time
  let last_modified_str = last_modified.utc.format("ddd, dd MMM yyyy HH:mm:ss 'GMT'")
  let etag = &"\"w/{file_info.size}.{last_modified_str}\""

  var resp_headers = new_http_headers([
    ("Content-Type", content_type),
    ("Last-Modified", last_modified_str),
    ("ETag", etag)
  ])

  # Check If-None-Match for conditional request (304 Not Modified)
  if client_headers.has_key("If-None-Match"):
    if client_headers["If-None-Match"] == etag:
      return ("", Http304, resp_headers)

  let is_user_content = dir in @["pictures", "avatars"]

  if "?v=" in req_path:
    # Versioned static assets: cache forever
    resp_headers.add("Cache-Control", "public, max-age=31536000, immutable")
  elif is_user_content:
    resp_headers.add("Cache-Control", "public, max-age=86400, must-revalidate")
  else:
    resp_headers.add("Cache-Control", "public, max-age=86400")

  return (read_file(full_path), Http200, resp_headers)

proc to_display_entries*(leaderboard: seq[tuple[walker: Walker, total_miles: float]]): seq[Entry] =
  for db_entry in leaderboard:
    result.add Entry(
      walker: Walker_Info(
        id: db_entry.walker.id,
        name: db_entry.walker.name,
        avatar_filename: db_entry.walker.avatar_filename,
      ),
      total_miles: db_entry.total_miles,
      progress_percent: min(db_entry.total_miles / 92.0 * 100.0, 100.0),
    )
