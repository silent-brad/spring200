import strutils, os, strformat, random
from times import format, now, getTime, toUnix
import std/sha1

# Initialize random seed with high-precision time and process id for uniqueness
randomize(get_time().to_unix() + get_current_process_id())

proc generate_random_filename*(extension: string = "webp",
    directory: string = ""): string =
  # Generate cryptographically random filename using timestamp + process ID + random data + SHA1
  let timestamp = $get_time().to_unix()
  let process_id = $get_current_process_id()

  # Generate random bytes for additional entropy
  var random_data = ""
  for i in 0..<32:
    random_data.add(char(rand(255)))

  # Combine timestamp, process ID, and random data, then hash
  let combined = timestamp & process_id & random_data
  let hash = $secure_hash(combined)

  # Take first 16 characters of hash for filename
  let base_filename = hash[0..15] & "." & extension

  # Check for collision and regenerate if needed (extremely unlikely but safe)
  if directory.len > 0:
    var final_filename = base_filename
    var counter = 0
    while file_exists(directory / final_filename) and counter < 1000:
      # Add counter to hash if collision detected
      let new_hash = $secure_hash(combined & $counter)
      final_filename = new_hash[0..15] & "." & extension
      inc(counter)
    return final_filename

  return base_filename

proc save_uploaded_file*(file_data: string, original_ext: string,
    directory: string = "pictures"): string =
  # Save uploaded file data to disk and return the filename
  if file_data.len == 0:
    return ""

  # Generate random filename
  let random_filename = generate_random_filename("webp", directory)

  # Ensure directory exists
  if not dir_exists(directory):
    create_dir(directory)

  # Check if file is already webp
  if original_ext == "webp":
    let filepath = directory / random_filename
    write_file(filepath, file_data)
    return random_filename
  else:
    # Save original file temporarily with random name
    let temp_filename = generate_random_filename(original_ext, directory)
    let temp_filepath = directory / temp_filename
    write_file(temp_filepath, file_data)

    # Convert to webp with random filename
    let webp_filepath = directory / random_filename

    # Use ImageMagick to convert to webp and resize
    try:
      var magick_cmd: string

      # Build ImageMagick command based on directory
      if directory == "avatars":
        # Resize to 400x400 square for avatars
        magick_cmd = &"magick \"{temp_filepath}\" -auto-orient -resize 400x400^ -gravity center -crop 400x400+0+0 +repage \"{webp_filepath}\""
      else:
        # Resize to max width 600 for other images, maintain aspect ratio
        magick_cmd = &"magick \"{temp_filepath}\" -auto-orient -resize 600 \"{webp_filepath}\""

      # Execute ImageMagick command
      let result = exec_shell_cmd(magick_cmd)

      if result == 0 and file_exists(webp_filepath):
        # Remove temporary file after successful conversion
        if file_exists(temp_filepath):
          remove_file(temp_filepath)
        return random_filename
      else:
        raise new_exception(IOError, "ImageMagick conversion failed")

    except Exception as e:
      # Fallback: save original file if conversion fails
      echo &"Image conversion failed: {e.msg}, saving original file"
      # Remove the temp file since we're keeping the original
      if file_exists(temp_filepath):
        remove_file(temp_filepath)
      # Save original file with original extension but random name
      let fallback_filename = generate_random_filename(original_ext, directory)
      let fallback_filepath = directory / fallback_filename
      write_file(fallback_filepath, file_data)
      return fallback_filename

proc parse_multipart_form*(body: string, boundary: string): seq[tuple[
    name: string, filename: string, content: string]] =
  # Parse multipart form data and extract file uploads
  var parts: seq[tuple[name: string, filename: string, content: string]] = @[]

  if body.len == 0 or boundary.len == 0:
    return parts

  let delimiter = "--" & boundary
  let sections = body.split(delimiter)

  for section in sections:
    if section.strip().len == 0 or section.strip() == "--":
      continue

    let lines = section.split("\r\n")
    if lines.len < 3:
      continue

    var name = ""
    var filename = ""
    var content = ""
    var content_start = -1

    # Parse headers
    for i, line in lines:
      if line.starts_with("Content-Disposition:"):
        # Extract name and filename from header
        for part in line.split(";"):
          let trimmed = part.strip()
          if trimmed.starts_with("name=\""):
            name = trimmed[6..^2] # Remove name=" and "
          elif trimmed.starts_with("filename=\""):
            filename = trimmed[10..^2] # Remove filename=" and "
      elif line.strip().len == 0 and content_start == -1:
        content_start = i + 1
        break

    # Extract content
    if content_start > 0 and content_start < lines.len:
      var content_lines: seq[string] = @[]
      for i in content_start..<lines.len:
        if lines[i].strip() == "--":
          break
        content_lines.add(lines[i])
      content = content_lines.join("\r\n").strip()

    if name.len > 0:
      parts.add((name, filename, content))

  return parts
