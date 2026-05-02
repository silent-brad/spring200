import asynchttpserver
import strutils, uri, tables, json, options, strformat
import ../database/[models, families, walkers, miles, posts]
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epoch_time, format
import ../types, ../auth, ../templates, ../utils
import common

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
    guard_walker(session)
    var success_msg: Option[string] = none(string)
    if req.url.query.len > 0:
      if "success=signup" in req.url.query:
        success_msg = some("Welcome to Spring92!")
      elif "success=login" in req.url.query:
        success_msg = some("Welcome back to Spring92!")
    const page_size = 15
    let leaderboard = get_leaderboard_paginated(db_conn, page_size + 1, 0)
    let has_more = leaderboard.len > page_size
    let display_leaderboard = if has_more: leaderboard[0 ..< page_size] else: leaderboard
    let user_stats = to_display_entries(display_leaderboard)
    response_body = render_leaderboard(session, success_msg,
        user_stats = user_stats, has_more = has_more,
        next_page = 2, offset = 0, current_page = 1)

  of "/dashboard":
    guard_walker(session)
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
    guard_walker(session)
    let current_total = get_user_total_miles(db_conn, session.get().walker_id)
    let progress_pct = min(current_total / 92.0 * 100.0, 100.0)
    response_body = render_template("dashboard.jinja", session,
        current_total = some(current_total), progress_percent = some(progress_pct))

  of "/posts":
    guard_walker(session)
    const page_size = 10
    let posts = get_posts_paginated(db_conn, page_size + 1, 0)
    let has_more = posts.len > page_size
    let display_posts = if has_more: posts[0 ..< page_size] else: posts
    response_body = render_posts_page(display_posts, session,
        has_more = has_more, next_page = 2)

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
    let user_id_opt = if session.is_some: some(session.get().walker_id) else: none(int64)
    response_body = render_template("about.jinja", session,
        walker_id = user_id_opt)

  of "/add-walker":
    guard_login(session)
    # Check for success parameter
    var success_msg: Option[string] = none(string)
    if req.url.query.len > 0:
      if "success=signup" in req.url.query:
        success_msg = some("Family account created successfully! Now create your first walker.")
    response_body = render_template("add-walker.jinja", session, none(string), success_msg)

  of "/select-walker":
    guard_login(session)
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
    guard_walker(session)
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
    guard_walker(session)
    response_body = render_template("delete_walker.jinja", session, none(string))

  of "/api/leaderboard-table":
    guard_walker(session)
    const page_size = 15
    var page = 1
    if req.url.query.len > 0 and req.url.query.starts_with("page="):
      try: page = parse_int(req.url.query[5..^1])
      except: discard
    let offset = (page - 1) * page_size
    let leaderboard = get_leaderboard_paginated(db_conn, page_size + 1, offset)
    let has_more = leaderboard.len > page_size
    let display_leaderboard = if has_more: leaderboard[0 ..< page_size] else: leaderboard
    let user_stats = to_display_entries(display_leaderboard)
    response_body = render_leaderboard_table(user_stats,
        has_more = has_more, next_page = page + 1,
        offset = offset, current_page = page)

  of "/api/user-miles-data":
    guard_json_unauthorized(session)
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
      miles_json.add(fmt_miles(entry.miles))

    for i, entry in recent_entries:
      if i > 0:
        entries_json.add(",")
      let formatted_date = format_date_with_ordinal(entry.logged_at)
      entries_json.add(&"""{{"id": {entry.id}, "date": "{formatted_date}", "miles": {fmtMiles(entry.miles)}}}""")

    dates_json.add("]")
    miles_json.add("]")
    entries_json.add("]")

    response_body = &"""{{"dates": {dates_json}, "miles": {miles_json}, "entries": {entries_json}}}"""

  of "/api/post-feed":
    guard_walker(session)
    const page_size = 10
    var page = 1
    if req.url.query.len > 0 and req.url.query.starts_with("page="):
      try: page = parse_int(req.url.query[5..^1])
      except: discard
    let offset = (page - 1) * page_size
    let posts = get_posts_paginated(db_conn, page_size + 1, offset)
    let has_more = posts.len > page_size
    let display_posts = if has_more: posts[0 ..< page_size] else: posts
    response_body = render_post_feed(display_posts, has_more = has_more,
        next_page = page + 1, session = session)

  # Handle switch-walker/ID routes
  elif req.url.path.starts_with("/switch-walker/"):
    guard_login(session)
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
    if req.url.path.starts_with("/static/"):
      return serve_static_file(req.url.path, "/static/", "static")
    elif req.url.path.starts_with("/pictures/"):
      return serve_static_file(req.url.path, "/pictures/", "pictures", check_safe_ext = true)
    elif req.url.path.starts_with("/avatars/"):
      return serve_static_file(req.url.path, "/avatars/", "avatars", check_safe_ext = true)
    else:
      status = Http404
      response_body = render_template("404.jinja", session)

  return (response_body, status, headers)
