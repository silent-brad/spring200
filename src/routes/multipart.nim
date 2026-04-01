import asyncdispatch
import asynchttpserver
import strutils
import strformat
import tables
import os
import sequtils
import ../utils

type
  MultipartData* = object
    fields*: Table[string, string]
    files*: Table[string, (string, string, int)] # (filename, contentType, size)
    error*: string

proc parseMultipart*(req: Request): Future[MultipartData] {.async.} =
  result = MultipartData(fields: initTable[string, string](), files: initTable[
      string, (string, string, int)](), error: "")

  if not req.headers.hasKey("content-type"):
    result.error = "Missing Content-Type"
    return

  let ctHeader = req.headers["content-type"]
  let contentType = ctHeader
  if not contentType.startsWith("multipart/form-data"):
    result.error = "Invalid Content-Type"
    return

  # Extract boundary more robustly by parsing parameters
  let params = contentType.split(';').mapIt(it.strip())
  var boundary = ""
  for param in params:
    if param.startsWith("boundary="):
      let boundaryRaw = param[9 .. ^1].strip()
      boundary = if boundaryRaw.startsWith('"') and boundaryRaw.endsWith(
          '"'): boundaryRaw[1 .. ^2] else: boundaryRaw
      break
  if boundary == "":
    result.error = "Missing boundary"
    return

  let fullBoundary = "--" & boundary

  # Get full body (already available as string)
  let body = req.body

  # Split into parts (parts[0] is preamble, last is epilogue)
  let parts = body.split(fullBoundary)
  if parts.len < 3 or not parts[^1].startsWith(
      "--"): # At least preamble, one part, epilogue; check final '--' for validity
    result.error = "Malformed multipart body"
    return

  for i in 1 ..< parts.len - 1:
    var part = parts[i].strip(leading = true, chars = {'\r', '\n'})
    if part.len == 0: continue

    # Find end of headers (\r\n\r\n)
    let headerEnd = part.find("\r\n\r\n")
    if headerEnd == -1: continue

    let headerStr = part[0 ..< headerEnd]
    var partBody = part[headerEnd + 4 .. ^1].strip(trailing = true, chars = {
        '\r', '\n'})

    # Parse part headers
    var part_headers = newTable[string, string]()
    for line in headerStr.split("\r\n"):
      if line.len == 0: continue
      let colonPos = line.find(':')
      if colonPos != -1:
        let key = line[0 ..< colonPos].strip().toLowerAscii()
        let val = line[colonPos + 1 .. ^1].strip()
        part_headers[key] = val

    # Parse Content-Disposition
    if not part_headers.hasKey("content-disposition"): continue
    let disp = part_headers["content-disposition"]
    if not disp.startsWith("form-data"): continue

    let dispParams = disp.split(';').mapIt(it.strip())
    var name = ""
    var filename = ""
    for param in dispParams[1 .. ^1]:
      let kv = param.split('=', 1)
      if kv.len != 2: continue
      let pkey = kv[0].strip()
      let pval = kv[1].strip(chars = {'"'})
      if pkey == "name": name = pval
      elif pkey == "filename": filename = pval

    if name.len == 0: continue

    let ctype = part_headers.get_or_default("content-type", "application/octet-stream")

    if filename.len > 0:
      # File upload - save to disk with proper security checks
      let upload_dir = "uploads"
      if not dir_exists(upload_dir): create_dir(upload_dir)

      # Sanitize filename and validate file extension
      let safe_filename = sanitize_filename(filename)
      if not is_safe_file_extension(safe_filename):
        result.error = "File type not allowed"
        return

      # Limit file size (10MB)
      if part_body.len > 10_485_760:
        result.error = "File too large"
        return

      let path = upload_dir / safe_filename
      write_file(path, part_body)
      result.files[name] = (safe_filename, ctype, part_body.len)
    else:
      # Regular field
      result.fields[name] = part_body
