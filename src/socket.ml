open Lwt
open Lwt_unix
open Lwt_io

let create () = socket PF_INET SOCK_STREAM 0
let bind address port socket = bind socket @@ ADDR_INET (address, port)
let listen max_pending_requests socket = listen socket max_pending_requests

let peername socket =
  match getpeername socket with
  | ADDR_INET (addr, port) ->
      Printf.sprintf "%s:%d" (Unix.string_of_inet_addr addr) port
  | _ -> ""

module Protocol = struct
  open Lwt.Syntax

  type side = Server_side | Client_side

  module Context = struct
    type t = { socket : file_descr; side : side }

    let make ~socket ~side = { socket; side }
  end

  let acknowledge = "Message received"
  let msg_flags = []
  let cancel_signal, cancel_wakeup = Lwt.wait ()

  let rec read_exactly socket buffer offset remaining =
    if remaining = 0 then return ()
    else
      let* bytes_read =
        Lwt_unix.recv socket buffer offset remaining msg_flags
      in
      read_exactly socket buffer (offset + bytes_read) (remaining - bytes_read)

  let rec send_exactly socket buffer offset remaining =
    if remaining = 0 then return ()
    else
      let* bytes_sent =
        Lwt_unix.send socket buffer offset remaining msg_flags
      in
      send_exactly socket buffer (offset + bytes_sent) (remaining - bytes_sent)

  let recv_opt socket =
    let len_buf = Bytes.create 4 in
    let* () = read_exactly socket len_buf 0 4 in
    let len = Bytes.get_int32_be len_buf 0 |> Int32.to_int in
    let msg_buf = Bytes.create len in
    let* () = read_exactly socket msg_buf 0 len in
    Some (Bytes.to_string msg_buf) |> return

  let rec recv_handler context () =
    let open Context in
    match state context.socket with
    | Opened ->
        Lwt.pick
          [
            ( recv_opt context.socket >>= fun message_opt ->
              match message_opt with
              | Some message ->
                  (if not (String.equal message acknowledge) then
                     let from =
                       match context.side with
                       | Server_side -> "client"
                       | Client_side -> "server"
                     in
                     printf "From %s: %s\n" from message |> ignore);

                  let msg_len = String.length acknowledge in
                  let msg_buf = Bytes.create (4 + msg_len) in
                  Bytes.set_int32_be msg_buf 0 (Int32.of_int msg_len);
                  Bytes.blit_string acknowledge 0 msg_buf 4 msg_len;
                  send_exactly context.socket msg_buf 0 (4 + msg_len)
                  >>= recv_handler context
              | None -> print "Connection closed.\n" >>= return );
            cancel_signal;
          ]
    | Closed -> print "Connection closed.\n" >>= return
    | Aborted exn ->
        exn |> Printexc.to_string |> printf "Connection aborted with error: %s"

  let is_client = function Client_side -> true | _ -> false

  let rec send_handler context () =
    let open Context in
    match state context.socket with
    | Opened ->
        Lwt.pick
          [
            ( read_line_opt stdin >>= fun message_opt ->
              match message_opt with
              | Some input -> (
                  if String.equal input "]" && is_client context.side then (
                    let* () = print "Closing connection...\n" in
                    wakeup cancel_wakeup ();
                    Lwt_unix.close context.socket)
                  else
                    let msg_len = String.length input in
                    let msg_buf = Bytes.create (4 + msg_len) in
                    Bytes.set_int32_be msg_buf 0 (Int32.of_int msg_len);
                    Bytes.blit_string input 0 msg_buf 4 msg_len;
                    let rtt_start = Unix.gettimeofday () in
                    let* () =
                      send_exactly context.socket msg_buf 0 (4 + msg_len)
                    in
                    let* ack_opt = recv_opt context.socket in
                    match ack_opt with
                    | Some ack ->
                        let rtt_end = Unix.gettimeofday () in
                        let rtt = rtt_end -. rtt_start in
                        printf "Ack: %s | Roundtrip Time: %fs\n" ack rtt
                        >>= send_handler context
                    | None ->
                        print "Acknowledgement not received.\n"
                        >>= send_handler context)
              | None -> send_handler context () );
            cancel_signal;
          ]
    | Closed -> return ()
    | Aborted exn ->
        exn |> Printexc.to_string
        |> printf "Connection aborted with error: %s\n"
end
