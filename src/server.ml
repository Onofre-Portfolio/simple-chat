open Lwt
open Socket

let address = Unix.inet_addr_loopback
let max_pending_requests = 10
let port = 8090

let start_connection connection =
  let socket, _sockaddr = connection in
  let in_channel = Lwt_io.of_fd ~mode:Lwt_io.Input socket in
  let out_channel = Lwt_io.of_fd ~mode:Lwt_io.Output socket in
  Lwt.on_failure
    (Lwt.join
       [
         Protocol.recv_handler Server_side in_channel out_channel ();
         Protocol.send_handler Server_side socket in_channel out_channel ();
       ])
    (fun err -> Printf.printf "%s\n" (Printexc.to_string err));
  let peername =
    match Lwt_unix.getpeername socket with
    | ADDR_INET (inet_addr, port) ->
        Printf.sprintf "%s:%d" (Unix.string_of_inet_addr inet_addr) port
    | ADDR_UNIX _ -> ""
  in
  Lwt_io.printf "New connection with %s.\n" peername >>= return

let create_socket () =
  let socket = Socket.create () in
  Socket.bind address port socket;
  Socket.listen max_pending_requests socket;
  socket

let start_server () =
  let open Lwt.Syntax in
  let* () = Lwt_io.print "Starting server...\n" in
  let socket = create_socket () in
  let rec server () = Lwt_unix.accept socket >>= start_connection >>= server in
  Lwt_io.printf "Listening on %s:%d.\n"
    (address |> Unix.string_of_inet_addr)
    port
  >>= server
