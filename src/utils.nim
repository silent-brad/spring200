import strutils, uri, tables, os
from times import DateTime, format, monthday, init_time

proc parse_form_data*(body: string): Table[string, string] =
  result = init_table[string, string]()
  if body.len == 0:
    return

  for pair in body.split("&"):
    let parts = pair.split("=", 1)
    if parts.len == 2:
      let key = parts[0].decode_url()
      let value = parts[1].decode_url()
      result[key] = value

proc html_escape*(s: string): string =
  ## Escape HTML special characters to prevent XSS attacks
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#x27;")

proc sanitize_html*(html: string): string =
  ## Sanitize HTML content allowing only safe tags and attributes
  result = html

  # Remove script tags and their content completely
  var start_pos = 0
  while true:
    let script_start = result.find("<script", start_pos)
    if script_start == -1: break
    let script_end = result.find("</script>", script_start)
    if script_end != -1:
      result.delete(script_start..script_end + 8)
      start_pos = script_start
    else:
      result.delete(script_start..result.len - 1)
      break

  # Remove dangerous event handlers (onclick, onload, etc.)
  let dangerous_attrs = @["onclick", "onload", "onerror", "onmouseover",
      "onfocus", "onblur", "onkeypress", "onsubmit", "onchange"]
  for attr in dangerous_attrs:
    result = result.replace(attr & "=", "data-removed-" & attr & "=")

  # Remove javascript: URLs
  result = result.replace("javascript:", "data-removed-javascript:")

  # Remove data: URLs for images (potential XSS vector)
  result = result.replace("data:", "data-removed:")

  # Keep only allowed tags: b, i, u, strong, em, a, h1-h6, blockquote, ul, ol, li, p, br, img
  # This is a simple approach - remove any tags not in allowed list
  let allowed_tags = @["b", "i", "u", "strong", "em", "a", "h1", "h2", "h3",
      "h4", "h5", "h6", "blockquote", "cite", "ul", "ol", "li", "p", "br", "img"]

  # Simple tag validation - remove disallowed tags
  var tag_start = 0
  while true:
    let open_bracket = result.find("<", tag_start)
    if open_bracket == -1: break

    let close_bracket = result.find(">", open_bracket)
    if close_bracket == -1: break

    let tag_content = result[open_bracket + 1..close_bracket - 1].strip()
    var tag_name = ""

    # Extract tag name (handle closing tags and attributes)
    if tag_content.starts_with("/"):
      tag_name = tag_content[1..^1].split(" ")[0].split("\t")[0]
    else:
      tag_name = tag_content.split(" ")[0].split("\t")[0]

    # Check if tag is allowed
    if tag_name.to_lower_ascii() notin allowed_tags and tag_name != "":
      # Remove the entire tag
      result.delete(open_bracket..close_bracket)
      tag_start = open_bracket
    else:
      # For allowed tags, sanitize attributes
      if tag_name.to_lower_ascii() == "a":
        # Only allow href attribute for links, remove others
        let href_start = tag_content.find("href=")
        if href_start != -1:
          result = result[0..open_bracket] & "a href=" & tag_content[
              href_start + 5..^1].split(" ")[0] & ">" & result[close_bracket + 1..^1]
        else:
          result = result[0..open_bracket] & "a>" & result[close_bracket + 1..^1]
      elif tag_name.to_lower_ascii() == "img":
        # Only allow src and alt attributes for images
        var new_attrs = ""
        let src_start = tag_content.find("src=")
        if src_start != -1:
          let src_value = tag_content[src_start + 4..^1].split(" ")[0]
          new_attrs.add("src=" & src_value)
        let alt_start = tag_content.find("alt=")
        if alt_start != -1:
          let alt_value = tag_content[alt_start + 4..^1].split(" ")[0]
          if new_attrs.len > 0: new_attrs.add(" ")
          new_attrs.add("alt=" & alt_value)
        result = result[0..open_bracket] & "img " & new_attrs & ">" & result[
            close_bracket + 1..^1]

      tag_start = close_bracket + 1

  return result

proc simple_format*(text: string): string =
  ## Convert line breaks to <br> tags for basic formatting
  result = html_escape(text) # First escape all HTML to prevent XSS
  result = result.replace("\n", "<br>")
  return result

proc sanitize_filename*(filename: string): string =
  ## Sanitize filename to prevent directory traversal
  result = filename
  # Remove path separators and dangerous characters
  result = result.replace("/", "")
  result = result.replace("\\", "")
  result = result.replace("..", "")
  result = result.replace(":", "")
  result = result.replace("*", "")
  result = result.replace("?", "")
  result = result.replace("\"", "")
  result = result.replace("<", "")
  result = result.replace(">", "")
  result = result.replace("|", "")
  # Ensure filename is not empty after sanitization
  if result.strip() == "":
    result = "unnamed_file"

proc sanitize_path*(path: string): string =
  ## Sanitize file paths to prevent directory traversal attacks
  result = path
  # Remove any path traversal attempts
  result = result.replace("..", "")
  result = result.replace("./", "")
  result = result.replace("~/", "")
  # Normalize path separators
  result = result.replace("\\", "/")
  # Remove any leading slashes that could access root
  result = result.strip(leading = true, chars = {'/'})

proc validate_email*(email: string): bool =
  ## Basic email validation to prevent injection
  if email.len == 0 or email.len > 254:
    return false
  # Simple validation without regex - check for @ and basic structure
  let at_pos = email.find('@')
  if at_pos == -1 or at_pos == 0 or at_pos == email.len - 1:
    return false
  let domain_part = email[at_pos + 1 .. ^1]
  let dot_pos = domain_part.rfind('.')
  if dot_pos == -1 or dot_pos == 0 or dot_pos == domain_part.len - 1:
    return false
  # Check for basic allowed characters
  for c in email:
    if not (c.is_alpha_numeric() or c in "@.-_+"):
      return false
  return true

proc validate_name*(name: string): bool =
  ## Validate name to prevent injection
  if name.len == 0 or name.len > 100:
    return false
  # Allow only letters, numbers, spaces, hyphens, apostrophes
  for c in name:
    if not (c.is_alpha_numeric() or c in " -'"):
      return false
  return true

proc is_safe_file_extension*(filename: string): bool =
  ## Check if file extension is safe for upload
  let allowed_extensions = @[".jpg", ".jpeg", ".png", ".gif", ".webp"]
  let ext = filename.split_file().ext.to_lower_ascii()
  return ext in allowed_extensions

proc fmt_miles*(miles: float): string =
  ## Format miles for display, rounding to 1 decimal place and stripping trailing .0
  let s = format_float(miles, ff_decimal, 1)
  if s.ends_with(".0"):
    return s[0 .. ^3]
  return s

proc error_div*(msg: string): string =
  """<div class="error solid">""" & msg & "</div>"

proc success_div*(msg: string): string =
  """<div class="success solid">""" & msg & "</div>"

proc html_error*(msg: string): string =
  """<p class="text-muted">""" & msg & "</p>"

proc html_success*(msg: string): string =
  """<p class="text-muted">""" & msg & "</p>"

const cookie_attrs* = "; HttpOnly; Path=/; Max-Age=2592000; SameSite=Lax"

proc format_date_with_ordinal*(dt: DateTime): string =
  ## Format date like "9:02pm, Dec 12th, 2025" with lowercase am/pm
  let day = dt.monthday()
  let suffix = if day mod 10 == 1 and day != 11: "st"
              elif day mod 10 == 2 and day != 12: "nd"
              elif day mod 10 == 3 and day != 13: "rd"
              else: "th"
  var time_part = dt.format("h:mmtt, MMM ")
  return time_part & $day & suffix & dt.format(", yyyy")
