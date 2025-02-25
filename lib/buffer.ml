type t = bytes

let prefix_length = 4
let msg_flags = []
let init = Bytes.create

let of_string message =
  let message_length = String.length message in
  let buffer = Bytes.create (prefix_length + message_length) in
  Bytes.set_int32_be buffer 0 (Int32.of_int message_length);
  Bytes.blit_string message 0 buffer prefix_length message_length;
  (message_length, buffer)

let to_string = Bytes.to_string

let rec send socket buffer offset remaining =
  let open Lwt in
  if remaining = 0 then return ()
  else
    Lwt_unix.send socket buffer offset remaining msg_flags >>= fun bytes_sent ->
    send socket buffer (offset + bytes_sent) (remaining - bytes_sent)

let rec read socket buffer offset remaining =
  let open Lwt in
  if remaining = 0 then return ()
  else
    Lwt_unix.recv socket buffer offset remaining msg_flags >>= fun bytes_read ->
    if bytes_read = 0 && remaining <> 0 then fail End_of_file
    else read socket buffer (offset + bytes_read) (remaining - bytes_read)

let prefix buf =
  let open Lwt in
  let prefix_buf = Bytes.create prefix_length in
  read buf prefix_buf 0 prefix_length >>= fun _bytes_read ->
  Bytes.get_int32_be prefix_buf 0 |> Int32.to_int |> return
