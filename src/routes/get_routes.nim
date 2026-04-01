import asynchttpserver
import strutils, uri, tables, json, options, strformat
import ../database/[models, families, walkers, miles, posts]
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epochTime, format
import ../types, ../auth, ../templates, ../utils

proc handle_get_routes*(req: Request, session: Option[Session],
    db_conn: DbConn): (string, HttpCode, HttpHeaders) =
  var response_body = ""
  var status = Http200
  var headers = new_http_headers([("Content-Type", "text/html")])

  case req.url.path:
  of "/":
    response_body = render_template("index.jinja", session)
  of "/login":
    response_body = render_template("login.jinja", session)
  of "/signup":
    response_body = render_template("signup.jinja", session)
  of "/leaderboard":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=signup" in req.url.query:
          success_msg = some("Welcome to Spring92!")
        elif "success=login" in req.url.query:
          success_msg = some("Welcome back to Spring92!")
      response_body = render_leaderboard(session, success_msg)

  of "/dashboard":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      let current_total = get_user_total_miles(db_conn, session.get().walker_id)
      let progress_pct = min(current_total / 92.0 * 100.0, 100.0)
      # Check for success parameter
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=signup" in req.url.query:
          success_msg = some("Account created successfully! Welcome to Spring92!")
        elif "success=login" in req.url.query:
          success_msg = some("Login successful! Welcome back to Spring92!")
      response_body = render_template("dashboard.jinja", session,
          success_message = success_msg, current_total = some(current_total),
          progress_percent = some(progress_pct))

  of "/log":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      let current_total = get_user_total_miles(db_conn, session.get().walker_id)
      let progress_pct = min(current_total / 92.0 * 100.0, 100.0)
      response_body = render_template("dashboard.jinja", session,
          current_total = some(current_total), progress_percent = some(progress_pct))

  of "/posts":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      response_body = render_posts_page(@[], session)

  of "/logout":
    if session.is_some:
      status = Http302
      headers = new_http_headers([
        ("Set-Cookie", "session_id=; HttpOnly; Path=/; Max-Age=0"),
        ("Location", "/")
      ])
    else:
      status = Http302
      headers = new_http_headers([("Location", "/")])

  of "/about":
    let user_id_opt = if session.isSome: some(session.get().walker_id) else: none(int64)
    response_body = render_template("about.jinja", session,
        walker_id = user_id_opt)

  of "/add-walker":
    if session.is_none:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      # Check for success parameter
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=signup" in req.url.query:
          success_msg = some("Family account created successfully! Now create your first walker.")
      response_body = render_template("add-walker.jinja", session, none(string), success_msg)

  of "/select-walker":
    if session.is_none:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      let db_walkers = get_walkers_by_family(db_conn, session.get().family_id)
      var walkers: seq[Walker_Info] = @[]
      for walker in db_walkers:
        let walker_info = Walker_Info(
          id: walker.id,
          name: walker.name,
          family_id: walker.family_id,
          has_custom_avatar: walker.has_custom_avatar,
          avatar_filename: walker.avatar_filename,
          created_at: $walker.created_at
        )
        walkers.add(walker_info)
      # Check for success parameter
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=login" in req.url.query:
          success_msg = some("Login successful! Choose a walker to continue.")
      response_body = render_walker_selection(walkers, session,
          success_message = success_msg)

  of "/settings":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      let user_opt = get_walker_by_id(db_conn, session.get().walker_id)
      if user_opt.is_some:
        let walker = user_opt.get()
        var user_info: Walker_Info = Walker_Info(id: walker.id,
            name: walker.name, avatar_filename: walker.avatar_filename)
        response_body = render_settings(some(user_info), session, none(string),
            none(string))
      else:
        status = Http302
        headers = new_http_headers([("Location", "/login")])

  of "/delete-walker":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      response_body = render_template("delete_walker.jinja", session, none(string))

  of "/api/leaderboard-table":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      let leaderboard = get_leaderboard(db_conn)
      var user_stats: seq[Entry] = @[]
      for db_entry in leaderboard:
        var id: int64 = db_entry.walker.id
        var name: string = db_entry.walker.name
        var walker: Walker_Info = Walker_Info(id: id, name: name,
            avatar_filename: db_entry.walker.avatar_filename)
        var entry: Entry = Entry(
          walker: walker,
          total_miles: db_entry.total_miles,
          progress_percent: min(db_entry.total_miles / 92.0 * 100.0, 100.0),
        )
        user_stats.add(entry)

      response_body = render_leaderboard_table(user_stats)

  of "/api/user-miles-data":
    if session.is_none or session.get().is_family_session:
      status = Http401
      headers = new_http_headers([("Content-Type", "application/json")])
      response_body = "{\"error\": \"Unauthorized\"}"
    else:
      headers = new_http_headers([("Content-Type", "application/json")])
      let walker_id = session.get().walker_id
      let miles_by_date = get_user_miles_by_date(db_conn, walker_id)
      let recent_entries = get_user_recent_entries(db_conn, walker_id, 10)

      var dates_json = "["
      var miles_json = "["
      var entries_json = "["

      for i, entry in miles_by_date:
        if i > 0:
          dates_json.add(",")
          miles_json.add(",")
        dates_json.add("\"" & entry.date & "\"")
        miles_json.add($entry.miles)

      for i, entry in recent_entries:
        if i > 0:
          entries_json.add(",")
        let formatted_date = format_date_with_ordinal(entry.logged_at)
        entries_json.add(&"""{{"id": {entry.id}, "date": "{formatted_date}", "miles": {entry.miles}}}""")

      dates_json.add("]")
      miles_json.add("]")
      entries_json.add("]")

      response_body = &"""{{"dates": {dates_json}, "miles": {miles_json}, "entries": {entries_json}}}"""

  of "/api/post-feed":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location",
          if session.is_none: "/login" else: "/select-walker")])
    else:
      let posts = get_all_posts(db_conn)
      response_body = render_post_feed(posts)

  # Handle switch-walker/ID routes
  elif req.url.path.starts_with("/switch-walker/"):
    if session.is_none:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      let walker_id_str = req.url.path[15..^1] # Remove "/switch-walker/"
      try:
        let walker_id = parse_biggest_int(walker_id_str)
        let walker_opt = get_walker_by_id(db_conn, walker_id)

        if walker_opt.is_none or walker_opt.get().family_id != session.get().family_id:
          status = Http302
          headers = new_http_headers([("Location",
              "/select-walker?error=invalid-walker")])
        else:
          # Switch to the walker
          let new_session = Session(
            family_id: session.get().family_id,
            walker_id: walker_id,
            email: session.get().email,
            name: walker_opt.get().name,
            avatar_filename: walker_opt.get().avatar_filename,
            is_family_session: false
          )

          # Update session
          let session_id = generate_session_id()
          {.cast(gcsafe).}:
            with_lock sessions_lock:
              sessions[session_id] = new_session

          status = Http302
          headers = new_http_headers([
            ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
            ("Location", "/dashboard")
          ])
      except:
        status = Http302
        headers = new_http_headers([("Location",
            "/select-walker?error=invalid-walker")])
  else:
    # Check if it's a static file request
    if req.url.path.starts_with("/static/"):
      let file_path = sanitize_path(req.url.path[8..^1]) # Remove "/static/" and sanitize
      let full_path = "static" / file_path

      # Ensure the file is within the static directory
      if file_path.contains("..") or not full_path.starts_with("static/"):
        status = Http403
        response_body = "Access denied"
      elif file_exists(full_path):
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
          else: "application/octet-stream"

        headers = new_http_headers([("Content-Type", content_type)])
        response_body = read_file(full_path)
      else:
        status = Http404
        response_body = "File not found"

    # Check if it's a picture file request
    elif req.url.path.starts_with("/pictures/"):
      let file_path = sanitize_path(req.url.path[10..^1]) # Remove "/pictures/" and sanitize
      let full_path = "pictures" / file_path

      # Ensure the file is within the pictures directory and has safe extension
      if file_path.contains("..") or not full_path.starts_with("pictures/"):
        status = Http403
        response_body = "Access denied"
      elif not is_safe_file_extension(file_path):
        status = Http403
        response_body = "File type not allowed"
      elif file_exists(full_path):
        let ext = split_file(full_path).ext.to_lower_ascii()
        let content_type = case ext:
          of ".png": "image/png"
          of ".jpg", ".jpeg": "image/jpeg"
          of ".gif": "image/gif"
          of ".webp": "image/webp"
          else: "application/octet-stream"

        headers = new_http_headers([("Content-Type", content_type)])
        response_body = read_file(full_path)
      else:
        status = Http404
        response_body = "File not found"

    # Check if it's a avatar file request
    elif req.url.path.starts_with("/avatars/"):
      let file_path = sanitize_path(req.url.path[9..^1]) # Remove "/avatars/" and sanitize
      let full_path = "avatars" / file_path

      # Ensure the file is within the avatars directory and has safe extension
      if file_path.contains("..") or not full_path.starts_with("avatars/"):
        status = Http403
        response_body = "Access denied"
      elif not is_safe_file_extension(file_path):
        status = Http403
        response_body = "File type not allowed"
      elif file_exists(full_path):
        let ext = split_file(full_path).ext.to_lower_ascii()
        let content_type = case ext:
          of ".png": "image/png"
          of ".jpg", ".jpeg": "image/jpeg"
          of ".gif": "image/gif"
          of ".webp": "image/webp"
          else: "application/octet-stream"

        headers = new_http_headers([("Content-Type", content_type)])
        response_body = read_file(full_path)
      else:
        status = Http404
        response_body = "File not found"

    else:
      status = Http404
      response_body = render_template("404.jinja", session)

  return (response_body, status, headers)
