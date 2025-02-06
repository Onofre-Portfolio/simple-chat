open Lwt
open Socket

let ensure_connection socket sockaddr =
  Lwt.catch
    (fun () ->
      let open Lwt.Syntax in
      let* () = Lwt_unix.connect socket sockaddr in
      let peername =
        match Lwt_unix.getpeername socket with
        | ADDR_INET (addr, port) ->
            Printf.sprintf "%s:%d" (Unix.string_of_inet_addr addr) port
        | ADDR_UNIX _ -> "Impossible"
      in
      Lwt_io.printf "Connected to the server %s\n" peername |> ignore;
      return true)
    (fun e ->
      let msg =
        match e with
        | Unix.Unix_error (Unix.ENOTCONN, _, _) ->
            "Couldn't establish a connection, check if the server is running."
        | Unix.Unix_error (Unix.ECONNREFUSED, _, _) ->
            "Connection refused, check if the server is running."
        | _ as unix_error ->
            unix_error |> Printexc.to_string
            |> Printf.sprintf "Unexpected error: %s"
      in
      Lwt_io.printf "%s\n" msg |> ignore;
      return false)

let start_client address port =
  let open Lwt.Syntax in
  let open Lwt_unix in
  let inet_addr = Unix.inet_addr_of_string address in
  let sockaddr = ADDR_INET (inet_addr, port) in
  let socket = create () in
  let* is_connected = ensure_connection socket sockaddr in
  if is_connected then
    let in_channel = Lwt_io.of_fd ~mode:Lwt_io.Input socket in
    let out_channel = Lwt_io.of_fd ~mode:Lwt_io.Output socket in
    Lwt.join
      [
        Protocol.send_handler Client_side socket in_channel out_channel ();
        Protocol.recv_handler Client_side in_channel out_channel ();
      ]
  else return ()
