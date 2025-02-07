open Lwt
open Lwt.Syntax
open Lwt_unix
open Lwt_io
open Socket

let address = Unix.inet_addr_loopback
let max_pending_requests = 10
let port = 8090

let start_connection connection =
  let socket, _sockaddr = connection in
  let in_channel = of_fd ~mode:Input socket in
  let out_channel = of_fd ~mode:Output socket in
  let context =
    Protocol.Context.make ~socket ~side:Protocol.Server_side ~in_channel
      ~out_channel
  in
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

let start_server () =
  let* () = print "Starting server...\n" in
  let* socket = create_socket () in
  let rec server () = accept socket >>= start_connection >>= server in
  printf "Listening on %s:%d.\n" (address |> Unix.string_of_inet_addr) port
  >>= server
