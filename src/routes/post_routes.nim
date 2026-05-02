import asynchttpserver, asyncdispatch
import strutils, uri, tables, json, options, strformat
import ../database/[models, families, walkers, miles, posts]
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epochTime, format
import ../types, ../auth, ../templates, ../utils, ../upload
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
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Email is required</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Password is required</div>"""
    elif not validate_email(email):
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid email format</div>"""
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
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/select-walker?success=login")
        ])
        response_body = """<div class="success" style="background-color: var(--success-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Login successful! Redirecting...</div>"""
      else:
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid email or password</div>"""

  of "/signup":
    let passkey = to_upper_ascii(form_data.get_or_default("passkey", "")).strip()
    let email = form_data.get_or_default("email", "").strip()
    let password = form_data.get_or_default("password", "").strip()

    if passkey == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Passkey is required</div>"""
    elif email == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Email is required</div>"""
    elif not validate_email(email):
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid email format</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Password is required</div>"""
    elif not (passkey == PASSKEY):
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid passkey</div>"""
    elif get_family_by_email(db_conn, email).is_some:
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Email already registered</div>"""
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
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/add-walker?success=signup")
        ])
        response_body = """<div class="success" style="background-color: var(--success-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Account created successfully!</div>"""
      except Exception as e:
        echo "Error creating account: ", e.msg
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Error creating account</div>"""

  of "/create-walker":
    if session.is_none:
      status = Http401
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">You must be logged in to create walkers</div>"""
    else:
      let name = form_data.get_or_default("name", "").strip()

      if name == "":
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Name is required</div>"""
      elif not validate_name(name):
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid name format</div>"""
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
            ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
            ("HX-Redirect", "/dashboard?success=walker-created")
          ])
          response_body = """<div class="success" style="background-color: var(--success-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Walker account created successfully!</div>"""
        except Exception as e:
          echo "Error creating walker: ", e.msg
          response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Error creating walker account</div>"""

  of "/log":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to log miles</p>"""
    else:
      let miles_str = form_data.get_or_default("miles", "")
      try:
        let miles = parse_float(miles_str)
        if miles <= 0:
          response_body = """<p style="color: var(--error-oklch-500);">Miles must be positive</p>"""
        elif miles > 50:
          response_body = """<p style="color: var(--error-oklch-500);">Miles cannot exceed 50 per entry</p>"""
        else:
          log_miles(db_conn, session.get().walker_id, miles)
          response_body = &"""<p style="color: var(--success-oklch-500);">Logged {miles:.1f} miles successfully!</p>"""
      except:
        response_body = """<p style="color: var(--error-oklch-500);">Invalid miles value</p>"""

  of "/post":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to create posts</p>"""
    else:
      # Parse multipart form data for file upload
      let multipart_data = await parse_multipart(req)

      if multipart_data.error != "":
        if multipart_data.error == "File too large":
          status = Http413
          response_body = """<p style="color: var(--error-oklch-500);">The uploaded file is too large. Maximum file size is 10MB.</p>"""
        elif multipart_data.error == "File type not allowed":
          status = Http415
          response_body = """<p style="color: var(--error-oklch-500);">The uploaded file type is not supported. Please use JPG, PNG, GIF, or WebP images.</p>"""
        else:
          status = Http400
          response_body = &"""<p style="color: var(--error-oklch-500);">Error processing your upload: {multipart_data.error}. Please try again.</p>"""
      else:
        let text_content = sanitize_html(multipart_data.fields.getOrDefault(
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
          response_body = &"""<p style="color: var(--error-oklch-500);">{upload_error}</p>"""
        elif text_content.strip() == "" and image_filename == "":
          response_body = """<p style="color: var(--error-oklch-500);">Please provide text content or an image for your post.</p>"""
        else:
          try:
            discard create_post(db_conn, session.get().walker_id, text_content, image_filename)
            headers = new_http_headers([("HX-Redirect", "/posts")])
            response_body = """<p style="color: var(--success-oklch-500);">Post created successfully!</p>"""
          except Exception as e:
            echo "Error creating post: ", e.msg
            status = Http500
            response_body = """<p style="color: var(--error-oklch-500);">Failed to save your post. Please try again later.</p>"""

  of "/settings":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to update settings</p>"""
    else:
      # Parse multipart form data for file upload
      let multipart_data = await parse_multipart(req)

      if multipart_data.error != "":
        response_body = &"""<p style="color: var(--error-oklch-500);">Error parsing form data: {multipart_data.error}</p>"""
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
          response_body = """<p style="color: var(--error-oklch-500);">Name is required</p>"""
        elif not validate_name(name):
          response_body = """<p style="color: var(--error-oklch-500);">Invalid name format</p>"""
        else:
          let walker_opt = get_walker_by_id(db_conn, session.get().walker_id)
          if walker_opt.is_none:
            response_body = """<p style="color: var(--error-oklch-500);">Walker not found</p>"""
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
              response_body = &"<p style=\"color: var(--success-oklch-500);\">Settings updated successfully!</p>"
            else:
              response_body = &"""<p style="color: var(--error-oklch-500);">{error_msg}</p>"""

  of "/edit-post":
    if session.is_none or session.get().is_family_session:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to edit posts</p>"""
    else:
      let multipart_data = await parse_multipart(req)

      if multipart_data.error != "":
        if multipart_data.error == "File too large":
          status = Http413
          response_body = """<p style="color: var(--error-oklch-500);">The uploaded file is too large. Maximum file size is 10MB.</p>"""
        elif multipart_data.error == "File type not allowed":
          status = Http415
          response_body = """<p style="color: var(--error-oklch-500);">The uploaded file type is not supported. Please use JPG, PNG, GIF, or WebP images.</p>"""
        else:
          status = Http400
          response_body = &"""<p style="color: var(--error-oklch-500);">Error processing your upload: {multipart_data.error}. Please try again.</p>"""
      else:
        let post_id_str = multipart_data.fields.get_or_default("post_id", "")
        try:
          let post_id = parse_biggest_int(post_id_str)
          let post = get_post_by_id(db_conn, post_id)
          if post.walker_id != session.get().walker_id:
            status = Http403
            response_body = """<p style="color: var(--error-oklch-500);">You can only edit your own posts</p>"""
          else:
            let text_content = sanitize_html(multipart_data.fields.getOrDefault(
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
              response_body = """<p style="color: var(--error-oklch-500);">Please provide text content or an image for your post.</p>"""
            else:
              update_post(db_conn, post_id, text_content, image_filename)
              headers = new_http_headers([("HX-Redirect", "/posts")])
              response_body = """<p style="color: var(--success-oklch-500);">Post updated successfully!</p>"""
        except:
          response_body = """<p style="color: var(--error-oklch-500);">Invalid post</p>"""

  of "/delete-post":
    if session.is_none or session.get().is_family_session:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to delete posts</p>"""
    else:
      let post_id_str = form_data.get_or_default("post_id", "")
      try:
        let post_id = parse_biggest_int(post_id_str)
        let post = get_post_by_id(db_conn, post_id)
        if post.walker_id != session.get().walker_id:
          status = Http403
          response_body = """<p style="color: var(--error-oklch-500);">You can only delete your own posts</p>"""
        else:
          # Remove associated image file
          if post.image_filename != "" and file_exists("pictures" / post.image_filename):
            remove_file("pictures" / post.image_filename)
          delete_post(db_conn, post_id)
          headers = new_http_headers([("HX-Redirect", "/posts")])
          response_body = """<p style="color: var(--success-oklch-500);">Post deleted successfully!</p>"""
      except:
        response_body = """<p style="color: var(--error-oklch-500);">Invalid post</p>"""

  of "/edit-miles":
    if session.is_none or session.get().is_family_session:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to edit miles</p>"""
    else:
      let entry_id_str = form_data.get_or_default("entry_id", "")
      let miles_str = form_data.get_or_default("miles", "")
      try:
        let entry_id = parse_biggest_int(entry_id_str)
        let entry = get_mile_entry_by_id(db_conn, entry_id)
        if entry.walker_id != session.get().walker_id:
          status = Http403
          response_body = """<p style="color: var(--error-oklch-500);">You can only edit your own entries</p>"""
        else:
          let miles = parse_float(miles_str)
          if miles <= 0:
            response_body = """<p style="color: var(--error-oklch-500);">Miles must be positive</p>"""
          elif miles > 50:
            response_body = """<p style="color: var(--error-oklch-500);">Miles cannot exceed 50 per entry</p>"""
          else:
            update_mile_entry(db_conn, entry_id, miles)
            response_body = &"""<p style="color: var(--success-oklch-500);">Updated to {miles:.1f} miles successfully!</p>"""
      except:
        response_body = """<p style="color: var(--error-oklch-500);">Invalid entry</p>"""

  of "/delete-miles":
    if session.is_none or session.get().is_family_session:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to delete miles</p>"""
    else:
      let entry_id_str = form_data.get_or_default("entry_id", "")
      try:
        let entry_id = parse_biggest_int(entry_id_str)
        let entry = get_mile_entry_by_id(db_conn, entry_id)
        if entry.walker_id != session.get().walker_id:
          status = Http403
          response_body = """<p style="color: var(--error-oklch-500);">You can only delete your own entries</p>"""
        else:
          delete_mile_entry(db_conn, entry_id)
          response_body = """<p style="color: var(--success-oklch-500);">Entry deleted successfully!</p>"""
      except:
        response_body = """<p style="color: var(--error-oklch-500);">Invalid entry</p>"""

  of "/delete-walker":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: var(--error-oklch-500);">You must be logged in to delete your account</p>"""
    else:
      try:
        delete_walker_account(db_conn, session.get().walker_id)
        # Clear session and redirect to home
        headers = new_http_headers([
          ("Set-Cookie", "session_id=; HttpOnly; Path=/; Max-Age=0"),
          ("HX-Redirect", "/?success=account-deleted")
        ])
        response_body = """<p style="color: var(--success-oklch-500);">Account deleted successfully!</p>"""
      except Exception as e:
        echo "Error deleting walker: ", e.msg
        response_body = """<p style="color: var(--error-oklch-500);">Error deleting account</p>"""

  else:
    status = Http404
    response_body = "Endpoint not found"

  return (response_body, status, headers)
