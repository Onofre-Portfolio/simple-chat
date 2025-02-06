type side = Server_side | Client_side

let create () = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_STREAM 0

let bind address port socket =
  Lwt_unix.bind socket @@ Lwt_unix.ADDR_INET (address, port) |> ignore

let listen max_pending_requests socket =
  Lwt_unix.listen socket max_pending_requests

module Protocol = struct
  open Lwt
  open Lwt.Syntax

  let acknowledge = "Message received"

  let rec recv_handler side in_channel out_channel () =
    Lwt_io.read_line_opt in_channel >>= fun message_opt ->
    match message_opt with
    | Some message ->
        (if not (String.equal message acknowledge) then
           let from =
             match side with Server_side -> "client" | Client_side -> "server"
           in
           Lwt_io.printf "From %s: %s\n" from message |> ignore);

        Lwt_io.write_line out_channel acknowledge
        >>= recv_handler side in_channel out_channel
    | None -> (
        match side with
        | Server_side -> Lwt_io.print "Connection closed.\n" >>= return
        | Client_side -> recv_handler side in_channel out_channel ())

  let is_client = function Client_side -> true | _ -> false

  let rec send_handler side socket_ in_channel out_channel () =
    let open Lwt_unix in
    let state = Lwt_unix.state socket_ in
    Lwt_io.read_line_opt Lwt_io.stdin >>= fun message_opt ->
    match (state, message_opt) with
    | Opened, Some input ->
        if String.equal input "]" && is_client side then
          Lwt_unix.shutdown socket_ Lwt_unix.SHUTDOWN_SEND |> return
        else
          let rtt_start = Unix.gettimeofday () in
          let* () = Lwt_io.write_line out_channel input in
          let* ack = Lwt_io.read_line in_channel in
          let rtt_end = Unix.gettimeofday () in
          let rtt = rtt_end -. rtt_start in
          Lwt_io.printf "Ack: %s | Round-Trip Time: %f\n" ack rtt
          >>= send_handler side socket_ in_channel out_channel
    | Opened, None -> send_handler side socket_ in_channel out_channel ()
    | Closed, _ | Aborted _, _ -> return ()
end
