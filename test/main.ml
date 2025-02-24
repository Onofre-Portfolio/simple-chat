open Alcotest_lwt
open Simple_chat
open Lwt

let localhost_address = Unix.inet_addr_loopback
let port = 9000

let string_of_file_descr_state = function
  | Lwt_unix.Opened -> "Opened"
  | Lwt_unix.Closed -> "Closed"
  | Lwt_unix.Aborted exn ->
      exn |> Printexc.to_string |> Printf.sprintf "Aborted %s"

let test_create_socket switch () =
  let socket = Socket.create () in
  let hook socket () = Lwt_unix.close socket in
  Lwt_switch.add_hook (Some switch) (hook socket);
  Alcotest.(check string)
    "Opened state"
    (string_of_file_descr_state Lwt_unix.Opened)
    (string_of_file_descr_state @@ Lwt_unix.state socket);
  return ()

let test_socket_bind switch () =
  let socket = Socket.create () in
  let hook socket () = Lwt_unix.close socket in
  Lwt_switch.add_hook (Some switch) (hook socket);
  Socket.bind localhost_address port socket >>= fun () ->
  let expected_address = "127.0.0.1:9000" in
  let actual_address =
    match Lwt_unix.getsockname socket with
    | Lwt_unix.ADDR_INET (addr, port) ->
        Printf.sprintf "%s:%d" (Unix.string_of_inet_addr addr) port
    | Lwt_unix.ADDR_UNIX _ -> ""
  in
  Alcotest.(check string) "Expected address" expected_address actual_address;
  return ()

let test_connection_between_client_and_server switch () =
  let server_socket = Socket.create () in
  let client_socket = Socket.create () in
  let hook c_socket s_socket () =
    Lwt_unix.close c_socket >>= fun () -> Lwt_unix.close s_socket
  in
  Lwt_switch.add_hook (Some switch) (hook client_socket server_socket);
  Socket.bind localhost_address port server_socket >>= fun () ->
  Socket.listen 10 server_socket;
  Lwt_unix.connect client_socket (Unix.ADDR_INET (localhost_address, port))
  >>= fun () ->
  Lwt_unix.accept server_socket >>= fun (listening_socket, _) ->
  let expected_server_address = "127.0.0.1:9000" in
  let expected_client_address =
    match Lwt_unix.getsockname client_socket with
    | Lwt_unix.ADDR_INET (addr, p) ->
        Printf.sprintf "%s:%d" (Unix.string_of_inet_addr addr) p
    | Lwt_unix.ADDR_UNIX _ -> ""
  in
  Alcotest.(check string)
    "Peername should match client address" expected_client_address
    (Socket.peername listening_socket);
  Alcotest.(check string)
    "peername should match server address" expected_server_address
    (Socket.peername client_socket);
  return ()

let test_recv_handler_closed _switch () =
  let socket = Socket.create () in
  Lwt_unix.close socket >>= fun () ->
  let context =
    Socket.Context.make ~descriptor:socket ~side:Socket.Server_side
  in
  Socket.Protocol.recv_handler context () >>= return

let test_send_handler_closed _switch () =
  let socket = Socket.create () in
  Lwt_unix.close socket >>= fun () ->
  let context =
    Socket.Context.make ~descriptor:socket ~side:Socket.Client_side
  in
  Socket.Protocol.send_handler context () >>= return

let () =
  let tests =
    [
      ( "Socket",
        [
          test_case "A fresh socket should be an opened file descriptor." `Quick
            test_create_socket;
          test_case "A binded socket should have the expected binded address."
            `Quick test_socket_bind;
          test_case "A client and server socket should connect as expected."
            `Quick test_connection_between_client_and_server;
        ] );
      ( "Handler",
        [
          test_case "recv_handler on closed socket should be resolved." `Quick
            test_recv_handler_closed;
          test_case "send_handler on closed socket should be resolved." `Quick
            test_send_handler_closed;
        ] );
    ]
  in
  Lwt_main.run @@ Alcotest_lwt.run "Socket module tests" tests
