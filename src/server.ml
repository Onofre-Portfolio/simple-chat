open Lwt
open Lwt.Syntax
open Lwt_unix
open Lwt_io
open Socket

let address = Unix.inet_addr_loopback
let max_pending_requests = 10
let port = 8091
let active_connection = ref (Unix.stdin |> of_unix_file_descr)

let start_connection connection =
  let socket, _sockaddr = connection in
  active_connection := socket;
  let context = Protocol.Context.make ~socket ~side:Protocol.Server_side in
  on_failure
    (join
       [ Protocol.recv_handler context (); Protocol.send_handler context () ])
    (fun err -> Printf.printf "Unexpected error: %s\n" (Printexc.to_string err));
  printf "New connection with %s.\n" (peername socket) >>= return

let create_server_socket () =
  let socket_ = Socket.create () in
  let* () = Socket.bind address port socket_ in
  Socket.listen max_pending_requests socket_;
  return socket_

let shutdown_signal, shutdown_wakeup = Lwt.wait ()

let handle_signal signal =
  print_endline "\nClosing connection...";
  wakeup_later shutdown_wakeup signal;
  Protocol.safe_shutdown !active_connection |> ignore;
  Lwt_unix.close !active_connection |> ignore

let start_server () =
  let _ = on_signal Sys.sigint handle_signal in
  catch
    (fun () ->
      let* () = print "Starting server...\n" in
      let* socket = create_server_socket () in
      let rec serve () = accept socket >>= start_connection >>= serve in
      printf "Listening on %s:%d.\n" (address |> Unix.string_of_inet_addr) port
      >>= fun () ->
      Lwt.pick [ serve (); shutdown_signal ] >>= fun _ -> return ())
    (fun exn ->
      let msg =
        match exn with
        | Unix.Unix_error (Unix.EADDRINUSE, _, _) -> "Port is already in use."
        | _ ->
            exn |> Printexc.to_string
            |> Printf.sprintf "Unexpected error launching server: %s"
      in
      printf "%s\n" msg >>= return)
