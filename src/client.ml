open Lwt

let start_client address port =
  let inet_addr = Unix.inet_addr_of_string address in
  let sockaddr = Lwt_unix.ADDR_INET (inet_addr, port) in
  let socket = Socket.create () in
  Lwt_unix.connect socket sockaddr |> ignore;
  let rec client () =
    Lwt_io.read_line_opt Lwt_io.stdin >>= fun input_opt ->
    match input_opt with
    | Some message ->
        if String.equal message "]" then
          Lwt_unix.shutdown socket Lwt_unix.SHUTDOWN_SEND |> return
        else
          (*let in_channel = Lwt_io.of_fd ~mode:Lwt_io.Input socket in*)
          let out_channel = Lwt_io.of_fd ~mode:Lwt_io.Output socket in
          Lwt_io.write_line out_channel message
          >>= client
    | None -> client ()
  in
  client ()
