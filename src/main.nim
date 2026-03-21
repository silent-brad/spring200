import asynchttpserver, asyncdispatch
import strutils, options
import db_connector/db_sqlite
import locks
import database, types, auth, routes, utils
import os

var db_conn: DbConn
var PASSKEY: string
# Read passkey from passkey file (`.PASSKEY.txt`)
if file_exists(".PASSKEY.txt"):
  PASSKEY = ".PASSKEY.txt".read_file().strip()
else:
  echo "No passkey provided"
  quit(1)

proc handle_request(req: Request) {.async, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      # Get session
      var session: Option[Session] = none(Session)
      if req.headers.has_key("Cookie"):
        let cookies = req.headers["Cookie"]
        for cookie in cookies.split(";"):
          let parts = cookie.strip().split("=")
          if parts.len == 2 and parts[0] == "session_id":
            session = get_user_from_session(parts[1])
      
      var response_body: string
      var status: HttpCode
      var headers: HttpHeaders

      case req.req_method:
      of Http_get:
        (response_body, status, headers) = handle_get_routes(req, session, db_conn)
      of Http_post:
        (response_body, status, headers) = await handle_post_routes(req, session, db_conn, PASSKEY)
      else:
        status = Http405
        headers = new_http_headers([("Content-Type", "text/html")])
        response_body = "Method not allowed"
      
      await req.respond(status, response_body, headers)
    
    except Exception as e:
      echo "Error: ", e.msg
      await req.respond(Http500, "Internal server error")

proc main() {.async.} =
  echo "Initializing database..."
  db_conn = init_database()
  echo "Database initialized."
  
  init_lock(sessions_lock)
  
  var server = new_async_http_server()
  echo "Starting Spring92 server on port ", port
  await server.serve(Port(port), handle_request)

when is_main_module:
  try:
    async_check main()
    run_forever()
  finally:
    discard
