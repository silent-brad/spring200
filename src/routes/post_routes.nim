import asynchttpserver, asyncdispatch
import strutils, uri, tables, json, options, strformat
import ../database/[models, families, walkers, miles, posts]
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epoch_time, format
import ../types, ../auth, ../templates, ../utils, ../upload
import common
import multipart

proc handle_post_routes*(req: Request, session: Option[Session],
    db_conn: DbConn, PASSKEY: string): Future[(string, HttpCode,
    HttpHeaders)] {.async.} =
  let content_length = if req.headers.has_key("content-length"): parse_int(
      $req.headers["content-length"]) else: 0
  var body = ""
  if content_length > 0:
    body = req.body

  let form_data = parse_form_data(body)

  var response_body = ""
  var status = Http200
  var headers = new_http_headers([("Content-Type", "text/html")])

  case req.url.path:
  of "/login":
    let email = form_data.get_or_default("email", "").strip()
    let password = form_data.get_or_default("password", "").strip()

    if email == "":
      response_body = error_div("Email is required")
    elif password == "":
      response_body = error_div("Password is required")
    elif not validate_email(email):
      response_body = error_div("Invalid email format")
    else:
      # Check family account
      let family_opt = get_family_by_email(db_conn, email)
      if family_opt.is_some and verify_password(password, family_opt.get().password_hash):
        let family = family_opt.get()
        let session_id = generate_session_id()
        {.cast(gcsafe).}:
          with_lock sessions_lock:
            sessions[session_id] = Session(
              family_id: family.id,
              email: email,
              is_family_session: true
            )
        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & cookie_attrs),
          ("HX-Redirect", "/select-walker?success=login")
        ])
        response_body = success_div("Login successful! Redirecting...")
      else:
        response_body = error_div("Invalid email or password")

  of "/signup":
    let passkey = to_upper_ascii(form_data.get_or_default("passkey", "")).strip()
    let email = form_data.get_or_default("email", "").strip()
    let password = form_data.get_or_default("password", "").strip()

    if passkey == "":
      response_body = error_div("Passkey is required")
    elif email == "":
      response_body = error_div("Email is required")
    elif not validate_email(email):
      response_body = error_div("Invalid email format")
    elif password == "":
      response_body = error_div("Password is required")
    elif not (passkey == PASSKEY):
      response_body = error_div("Invalid passkey")
    elif get_family_by_email(db_conn, email).is_some:
      response_body = error_div("Email already registered")
    else:
      try:
        let password_hash = hash_password(password)
        let family_id = create_family_account(db_conn, email, password_hash)

        let session_id = generate_session_id()
        {.cast(gcsafe).}:
          with_lock sessions_lock:
            sessions[session_id] = Session(family_id: family_id, walker_id: 0,
                email: email, is_family_session: true)

        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & cookie_attrs),
          ("HX-Redirect", "/add-walker?success=signup")
        ])
        response_body = success_div("Account created successfully!")
      except Exception as e:
        echo "Error creating account: ", e.msg
        response_body = error_div("Error creating account")

  of "/create-walker":
    if session.is_none: return post_unauthorized("You must be logged in to create walkers")
    let name = form_data.get_or_default("name", "").strip()

    if name == "":
      response_body = error_div("Name is required")
    elif not validate_name(name):
      response_body = error_div("Invalid name format")
    else:
      try:
        let (walker_id, avatar_filename) = create_walker_account(db_conn,
            session.get().family_id, name)

        # Switch to the new walker
        let new_session = Session(
          family_id: session.get().family_id,
          walker_id: walker_id,
          email: session.get().email,
          name: name,
          avatar_filename: avatar_filename,
          is_family_session: false
        )

        # Update session
        let session_id = generate_session_id()
        {.cast(gcsafe).}:
          with_lock sessions_lock:
            sessions[session_id] = new_session

        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & cookie_attrs),
          ("HX-Redirect", "/dashboard?success=walker-created")
        ])
        response_body = success_div("Walker account created successfully!")
      except Exception as e:
        echo "Error creating walker: ", e.msg
        response_body = error_div("Error creating walker account")

  of "/log":
    if session.is_none: return post_unauthorized("You must be logged in to log miles")
    let miles_str = form_data.get_or_default("miles", "")
    try:
      let miles = parse_float(miles_str)
      if miles <= 0:
        response_body = html_error("Miles must be positive")
      elif miles > 50:
        response_body = html_error("Miles cannot exceed 50 per entry")
      else:
        log_miles(db_conn, session.get().walker_id, miles)
        response_body = html_success(&"Logged {miles:.1f} miles successfully!")
    except:
      response_body = html_error("Invalid miles value")

  of "/post":
    if session.is_none: return post_unauthorized("You must be logged in to create posts")
    let multipart_data = await parse_multipart(req)

    if multipart_data.error != "":
      if multipart_data.error == "File too large":
        status = Http413
        response_body = html_error("The uploaded file is too large. Maximum file size is 10MB.")
      elif multipart_data.error == "File type not allowed":
        status = Http415
        response_body = html_error("The uploaded file type is not supported. Please use JPG, PNG, GIF, or WebP images.")
      else:
        status = Http400
        response_body = html_error(&"Error processing your upload: {multipart_data.error}. Please try again.")
    else:
      let text_content = sanitize_html(multipart_data.fields.get_or_default(
          "text_content", "").strip())
      var image_filename = ""
      var upload_error = ""
      if multipart_data.files.has_key("image"):
        let (orig_filename, content_type, file_size) = multipart_data.files["image"]
        let upload_path = "uploads" / orig_filename
        if file_exists(upload_path):
          try:
            let file_data = read_file(upload_path)
            # Extract extension from original filename
            let original_ext = if orig_filename.contains(
                "."): orig_filename.split(".")[^1].to_lower_ascii() else: "jpg"
            image_filename = save_uploaded_file(file_data, original_ext, "pictures")
            # Clean up the temporary file
            remove_file(upload_path)
          except Exception as e:
            echo "Error processing uploaded file: ", e.msg
            upload_error = "Failed to process the uploaded image. Please try a different file."
            # Clean up temp file on error
            if file_exists(upload_path):
              remove_file(upload_path)
        else:
          upload_error = "The uploaded file could not be saved. Please try again."

      if upload_error != "":
        status = Http500
        response_body = html_error(upload_error)
      elif text_content.strip() == "" and image_filename == "":
        response_body = html_error("Please provide text content or an image for your post.")
      else:
        try:
          discard create_post(db_conn, session.get().walker_id, text_content, image_filename)
          headers = new_http_headers([("HX-Redirect", "/posts")])
          response_body = html_success("Post created successfully!")
        except Exception as e:
          echo "Error creating post: ", e.msg
          status = Http500
          response_body = html_error("Failed to save your post. Please try again later.")

  of "/settings":
    if session.is_none: return post_unauthorized("You must be logged in to update settings")
    let multipart_data = await parse_multipart(req)

    if multipart_data.error != "":
      response_body = html_error(&"Error parsing form data: {multipart_data.error}")
    else:
      # Extract form fields with validation
      let name = multipart_data.fields.get_or_default("name", "").strip()
      let current_password = multipart_data.fields.get_or_default(
          "current_password", "").strip()
      let new_password = multipart_data.fields.get_or_default("new_password",
          "").strip()
      let confirm_password = multipart_data.fields.get_or_default(
          "confirm_new_password", "").strip()

      if name == "":
        response_body = html_error("Name is required")
      elif not validate_name(name):
        response_body = html_error("Invalid name format")
      else:
        let walker_opt = get_walker_by_id(db_conn, session.get().walker_id)
        if walker_opt.is_none:
          response_body = html_error("Walker not found")
        else:
          let walker = walker_opt.get()
          var success = true
          var error_msg = ""

          # Update basic info
          if success:
            try:
              update_walker_name(db_conn, walker.id, name)
            except:
              success = false
              error_msg = "Error updating profile"

          # Handle avatar upload if provided
          if success and multipart_data.files.has_key("avatar"):
            let (orig_filename, content_type,
              file_size) = multipart_data.files["avatar"]
            let upload_path = "uploads" / orig_filename
            if file_exists(upload_path):
              try:
                let file_data = read_file(upload_path)
                # Extract extension from original filename
                let original_ext = if orig_filename.contains(
                    "."): orig_filename.split(".")[^1].to_lower_ascii() else: "jpg"
                # Save to avatars directory, allowing overwrite of existing file
                let avatar_filename = save_uploaded_file(file_data,
                    original_ext, "avatars")
                # Clean up the temporary file
                remove_file(upload_path)
                # Update walker avatar flag in database
                update_walker_avatar(db_conn, avatar_filename, session.get().walker_id)
                # Update existing session with new avatar
                var current_session_id: string = ""
                if req.headers.has_key("Cookie"):
                  let cookies = req.headers["Cookie"]
                  for cookie in cookies.split(";"):
                    let parts = cookie.strip().split("=")
                    if parts.len == 2 and parts[0] == "session_id":
                      current_session_id = parts[1]
                      break

                if current_session_id != "":
                  {.cast(gcsafe).}:
                    with_lock sessions_lock:
                      sessions[current_session_id] = Session(
                        family_id: session.get().family_id,
                        walker_id: session.get().walker_id,
                        email: session.get().email,
                        name: session.get().name,
                        avatar_filename: avatar_filename,
                        is_family_session: false
                      )
              except Exception as e:
                echo "Error updating avatar: ", e.msg
                success = false
                error_msg = "Error updating avatar"

          # Handle password change if provided
          if success and current_password != "" and new_password != "":
            if new_password != confirm_password:
              success = false
              error_msg = "New passwords do not match"
            elif new_password.len < 8:
              success = false
              error_msg = "Password must be at least 8 characters"
            else:
              # Verify current family password
              let family_opt = get_family_by_id(db_conn, session.get().family_id)
              if family_opt.is_none:
                success = false
                error_msg = "Family account not found"
              elif not verify_password(current_password, family_opt.get().password_hash):
                success = false
                error_msg = "Current password is incorrect"
              else:
                try:
                  let new_password_hash = hash_password(new_password)
                  update_family_password(db_conn, session.get().family_id, new_password_hash)
                except:
                  success = false
                  error_msg = "Error updating password"

          if success:
            headers = new_http_headers([("HX-Redirect",
                "/dashboard?success=settings")])
            response_body = html_success("Settings updated successfully!")
          else:
            response_body = html_error(error_msg)

  of "/edit-post":
    if session.is_none or session.get().is_family_session: return post_unauthorized("You must be logged in to edit posts")
    let multipart_data = await parse_multipart(req)

    if multipart_data.error != "":
      if multipart_data.error == "File too large":
        status = Http413
        response_body = html_error("The uploaded file is too large. Maximum file size is 10MB.")
      elif multipart_data.error == "File type not allowed":
        status = Http415
        response_body = html_error("The uploaded file type is not supported. Please use JPG, PNG, GIF, or WebP images.")
      else:
        status = Http400
        response_body = html_error(&"Error processing your upload: {multipart_data.error}. Please try again.")
    else:
      let post_id_str = multipart_data.fields.get_or_default("post_id", "")
      try:
        let post_id = parse_biggest_int(post_id_str)
        let post = get_post_by_id(db_conn, post_id)
        if post.walker_id != session.get().walker_id:
          status = Http403
          response_body = html_error("You can only edit your own posts")
        else:
          let text_content = sanitize_html(multipart_data.fields.get_or_default(
              "text_content", "").strip())
          var image_filename = post.image_filename
          let remove_image = multipart_data.fields.get_or_default("remove_image", "") == "1"

          if remove_image:
            if image_filename != "" and file_exists("pictures" / image_filename):
              remove_file("pictures" / image_filename)
            image_filename = ""

          if multipart_data.files.has_key("image"):
            let (orig_filename, content_type, file_size) = multipart_data.files["image"]
            let upload_path = "uploads" / orig_filename
            if file_exists(upload_path):
              try:
                let file_data = read_file(upload_path)
                let original_ext = if orig_filename.contains(
                    "."): orig_filename.split(".")[^1].to_lower_ascii() else: "jpg"
                # Remove old image if replacing
                if post.image_filename != "" and file_exists("pictures" / post.image_filename):
                  remove_file("pictures" / post.image_filename)
                image_filename = save_uploaded_file(file_data, original_ext, "pictures")
                remove_file(upload_path)
              except Exception as e:
                echo "Error processing uploaded file: ", e.msg
                if file_exists(upload_path):
                  remove_file(upload_path)

          if text_content.strip() == "" and image_filename == "":
            response_body = html_error("Please provide text content or an image for your post.")
          else:
            update_post(db_conn, post_id, text_content, image_filename)
            headers = new_http_headers([("HX-Redirect", "/posts")])
            response_body = html_success("Post updated successfully!")
      except:
        response_body = html_error("Invalid post")

  of "/delete-post":
    if session.is_none or session.get().is_family_session: return post_unauthorized("You must be logged in to delete posts")
    let post_id_str = form_data.get_or_default("post_id", "")
    try:
      let post_id = parse_biggest_int(post_id_str)
      let post = get_post_by_id(db_conn, post_id)
      if post.walker_id != session.get().walker_id:
        status = Http403
        response_body = html_error("You can only delete your own posts")
      else:
        # Remove associated image file
        if post.image_filename != "" and file_exists("pictures" / post.image_filename):
          remove_file("pictures" / post.image_filename)
        delete_post(db_conn, post_id)
        headers = new_http_headers([("HX-Redirect", "/posts")])
        response_body = html_success("Post deleted successfully!")
    except:
      response_body = html_error("Invalid post")

  of "/edit-miles":
    if session.is_none or session.get().is_family_session: return post_unauthorized("You must be logged in to edit miles")
    let entry_id_str = form_data.get_or_default("entry_id", "")
    let miles_str = form_data.get_or_default("miles", "")
    try:
      let entry_id = parse_biggest_int(entry_id_str)
      let entry = get_mile_entry_by_id(db_conn, entry_id)
      if entry.walker_id != session.get().walker_id:
        status = Http403
        response_body = html_error("You can only edit your own entries")
      else:
        let miles = parse_float(miles_str)
        if miles <= 0:
          response_body = html_error("Miles must be positive")
        elif miles > 50:
          response_body = html_error("Miles cannot exceed 50 per entry")
        else:
          update_mile_entry(db_conn, entry_id, miles)
          response_body = html_success(&"Updated to {miles:.1f} miles successfully!")
    except:
      response_body = html_error("Invalid entry")

  of "/delete-miles":
    if session.is_none or session.get().is_family_session: return post_unauthorized("You must be logged in to delete miles")
    let entry_id_str = form_data.get_or_default("entry_id", "")
    try:
      let entry_id = parse_biggest_int(entry_id_str)
      let entry = get_mile_entry_by_id(db_conn, entry_id)
      if entry.walker_id != session.get().walker_id:
        status = Http403
        response_body = html_error("You can only delete your own entries")
      else:
        delete_mile_entry(db_conn, entry_id)
        response_body = html_success("Entry deleted successfully!")
    except:
      response_body = html_error("Invalid entry")

  of "/delete-walker":
    if session.is_none: return post_unauthorized("You must be logged in to delete your account")
    try:
      delete_walker_account(db_conn, session.get().walker_id)
      # Clear session and redirect to home
      headers = new_http_headers([
        ("Set-Cookie", "session_id=; HttpOnly; Path=/; Max-Age=0"),
        ("HX-Redirect", "/?success=account-deleted")
      ])
      response_body = html_success("Account deleted successfully!")
    except Exception as e:
      echo "Error deleting walker: ", e.msg
      response_body = html_error("Error deleting account")

  else:
    status = Http404
    response_body = "Endpoint not found"

  return (response_body, status, headers)
