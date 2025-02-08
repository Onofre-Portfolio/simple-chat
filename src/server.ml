open Lwt
open Lwt.Syntax
open Lwt_unix
open Lwt_io
open Socket

let address = Unix.inet_addr_loopback
let max_pending_requests = 10
let port = 8090
let active_connection = ref (Unix.stdin |> of_unix_file_descr)

let start_connection connection =
  let socket, _sockaddr = connection in
  active_connection := socket;
  let context = Protocol.Context.make ~socket ~side:Protocol.Server_side in
  Lwt.on_failure
    (Lwt.join
       [ Protocol.recv_handler context (); Protocol.send_handler context () ])
    (fun err -> Printf.printf "%s\n" (Printexc.to_string err));
  let peername =
    match getpeername socket with
    | ADDR_INET (inet_addr, port) ->
        Printf.sprintf "%s:%d" (Unix.string_of_inet_addr inet_addr) port
    | ADDR_UNIX _ -> ""
  in
  printf "New connection with %s.\n" peername >>= return

let create_socket () =
  let socket_ = Socket.create () in
  let* () = Socket.bind address port socket_ in
  Socket.listen max_pending_requests socket_;
  return socket_

let shutdown_signal, shutdown_wakeup = Lwt.wait ()

let handle_signal signal =
  print_endline "\nServer is shutting down...";
  Lwt_unix.close !active_connection |> ignore;
  wakeup_later shutdown_wakeup signal

let start_server () =
  let _ = on_signal Sys.sigint handle_signal in
  catch
    (fun () ->
      let* () = print "Starting server...\n" in
      let* socket = create_socket () in
      let rec server () = accept socket >>= start_connection >>= server in
      printf "Listening on %s:%d.\n" (address |> Unix.string_of_inet_addr) port
      >>= fun () ->
      Lwt.pick [ server (); shutdown_signal ] >>= fun _ -> return ())
    (fun exn ->
      let msg =
        match exn with
        | Unix.Unix_error (Unix.EADDRINUSE, _, _) -> "Port is already in use."
        | _ as err ->
            err |> Printexc.to_string
            |> Printf.sprintf "Unexpected error launching server: %s"
      in
      printf "%s\n" msg >>= return)
