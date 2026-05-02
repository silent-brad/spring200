import tables
import times

type
  Session* = object
    family_id*: int64
    walker_id*: int64
    email*: string
    name*: string
    avatar_filename*: string
    is_family_session*: bool # true if logged into family account, false if in walker

  Walker_Info* = object
    id*: int64
    name*: string
    family_id*: int64
    avatar_filename*: string
    has_custom_avatar*: bool
    created_at*: string

  Entry* = object
    walker*: Walker_Info
    total_miles*: float
    progress_percent*: float

  Post* = object
    id*: int64
    walker_id*: int64
    name*: string
    avatar_filename*: string
    text_content*: string
    image_filename*: string
    created_at*: DateTime

const
  static_dir* = "static"
  port* = 8084

var sessions* {.global.}: Table[string, Session]
