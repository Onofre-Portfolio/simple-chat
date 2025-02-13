open Lwt
open Lwt_unix
open Lwt_io
open Socket

let address = Unix.inet_addr_any
let max_pending_requests = 10
let default_port = 8090
let active_connection = ref (Unix.stdin |> of_unix_file_descr)

let start_connection connection =
  let socket, _sockaddr = connection in
  active_connection := socket;
  let context = Protocol.Context.make ~socket ~side:Protocol.Server_side in
  on_failure
    (join
       [ Protocol.recv_handler context (); Protocol.send_handler context () ])
    (fun err -> Printf.printf "Unexpected error: %s\n" (Printexc.to_string err));
  printf "New connection with %s.\n" @@ peername socket >>= return

let create_server_socket port =
  let socket_ = Socket.create () in
  Socket.bind address port socket_ >>= fun () ->
  Socket.listen max_pending_requests socket_;
  return socket_

let shutdown_thread, shutdown_resolver = Lwt.wait ()

let handle_shutdown_signal signal =
  print "\nClosing connection and shutting down the server...\n" |> ignore;
  wakeup_later shutdown_resolver signal;
  Protocol.safe_close !active_connection |> ignore

let start port_opt =
  let port = match port_opt with Some p -> p | None -> default_port in
  let _ = on_signal Sys.sigint handle_shutdown_signal in
  catch
    (fun () ->
      print "Starting server...\n" >>= fun () ->
      create_server_socket port >>= fun socket ->
      let rec serve () = accept socket >>= start_connection >>= serve in
      printf "Listening on %s:%d.\n" (address |> Unix.string_of_inet_addr) port
      >>= fun () ->
      pick [ serve (); shutdown_thread ] >>= fun _ -> return ())
    (fun exn ->
      let msg =
        match exn with
        | Unix.Unix_error (Unix.EADDRINUSE, _, _) -> "Port is already in use."
        | _ ->
            exn |> Printexc.to_string
            |> Printf.sprintf "Unexpected error launching server: %s"
      in
      printf "%s\n" msg >>= return)
