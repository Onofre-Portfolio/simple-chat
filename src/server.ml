open Lwt

let acknowledge_string = "Message received."
let address = Unix.inet_addr_loopback
let max_pending_requests = 10
let port = 8090

let print_message message =
  Printf.sprintf "Message: %s" message |> print_endline

let rec message_handler input_channel output_channel () =
  Lwt_io.read_line_opt input_channel >>= fun message_opt ->
  match message_opt with
  | Some message ->
      message |> print_message;
      Lwt_io.write_line output_channel acknowledge_string
      >>= message_handler input_channel output_channel
  | None -> Lwt_io.print "Connection closed.\n" >>= return

let rec stdin_handler descriptor_state output_channel () =
  let open Lwt_unix in
  Lwt_io.read_line_opt Lwt_io.stdin >>= fun message_opt ->
  match (descriptor_state, message_opt) with
  | Opened, Some message ->
      message |> print_message;
      Lwt_io.write_line output_channel message
      >>= stdin_handler descriptor_state output_channel
  | Opened, None -> stdin_handler descriptor_state output_channel ()
  | Closed, _ | Aborted _, _ -> return ()

let start_connection connection =
  let file_descriptor, _ = connection in
  let descriptor_state = Lwt_unix.state file_descriptor in
  let input_channel = Lwt_io.of_fd ~mode:Lwt_io.Input file_descriptor in
  let output_channel = Lwt_io.of_fd ~mode:Lwt_io.Output file_descriptor in
  Lwt.on_failure
    (Lwt.join
       [
         message_handler input_channel output_channel ();
         stdin_handler descriptor_state output_channel ();
       ])
    (fun err -> Printf.printf "%s\n" (Printexc.to_string err));
  let peername =
    match Lwt_unix.getpeername file_descriptor with
    | ADDR_INET (inet_addr, port) ->
        Printf.sprintf "%s:%d" (Unix.string_of_inet_addr inet_addr) port
    | ADDR_UNIX _ -> ""
  in
  Lwt_io.printf "New connection with %s.\n" peername >>= return

let create_socket_V2 () =
  let socket = Socket.create () in
  Socket.bind address port socket;
  Socket.listen max_pending_requests socket;
  socket

let start_server () =
  let open Lwt.Syntax in
  let* () = Lwt_io.print "Starting server...\n" in
  let socket = create_socket_V2 () in
  let rec server () = Lwt_unix.accept socket >>= start_connection >>= server in
  Lwt_io.printf "Listening on %s:%d.\n"
    (address |> Unix.string_of_inet_addr)
    port
  >>= server
