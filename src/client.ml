open Lwt
open Lwt.Syntax
open Lwt_unix
open Lwt_io
open Socket

let ensure_initial_connection socket sockaddr =
  catch
    (fun () ->
      let* () = connect socket sockaddr in
      getpeername socket |> ignore;
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
      printf "%s\n" msg |> ignore;
      return false)

let start_client address port =
  let inet_addr = Unix.inet_addr_of_string address in
  let sockaddr = ADDR_INET (inet_addr, port) in
  let socket = create () in
  let* is_connected = ensure_initial_connection socket sockaddr in
  if is_connected then
    let peername = Socket.peername socket in
    let* () = printf "Connected to %s\n" peername in
    let in_channel = of_fd ~mode:Input socket in
    let out_channel = of_fd ~mode:Output socket in
    let context =
      Protocol.Context.make ~socket ~side:Protocol.Client_side ~in_channel
        ~out_channel
    in
    join [ Protocol.send_handler context (); Protocol.recv_handler context () ]
  else return ()
