open Lwt
open Lwt_unix
open Lwt_io
open Socket

let ensure_initial_connection socket sockaddr =
  catch
    (fun () ->
      connect socket sockaddr >>= fun () ->
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

let start address port =
  let inet_addr = Unix.inet_addr_of_string address in
  let sockaddr = ADDR_INET (inet_addr, port) in
  let socket = create () in
  ensure_initial_connection socket sockaddr >>= function
  | true ->
      let peername = Socket.peername socket in
      printf "Connected to %s\n" peername >>= fun () ->
      let context = Context.make ~descriptor:socket ~side:Client_side in
      join
        [ Protocol.send_handler context (); Protocol.recv_handler context () ]
  | false -> return ()
