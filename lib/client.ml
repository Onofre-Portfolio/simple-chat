let ensure_initial_connection socket sockaddr =
  let open Lwt in
  catch
    (fun () ->
      Lwt_unix.connect socket sockaddr >>= fun () ->
      Lwt_unix.getpeername socket |> ignore;
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

let start address port =
  let open Lwt in
  let inet_addr = Unix.inet_addr_of_string address in
  let sockaddr = Lwt_unix.ADDR_INET (inet_addr, port) in
  let socket = Socket.create () in
  ensure_initial_connection socket sockaddr >>= function
  | true ->
      let peername = Socket.peername socket in
      Lwt_io.printf "Connected to %s\n" peername >>= fun () ->
      let context = Socket.Context.make ~descriptor:socket ~side:Client_side in
      join
        [
          Socket.Protocol.send_handler context ();
          Socket.Protocol.recv_handler context ();
        ]
  | false -> return ()
