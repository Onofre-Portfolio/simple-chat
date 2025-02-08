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
    type t = {
      socket : file_descr;
      side : side;
      in_channel : input_channel;
      out_channel : output_channel;
    }

    let make ~socket ~side ~in_channel ~out_channel =
      { socket; side; in_channel; out_channel }
  end

  let acknowledge = "Message received"
  let cancel_signal, cancel_wakeup = Lwt.wait ()

  let rec recv_handler context () =
    let open Context in
    match state context.socket with
    | Opened ->
        Lwt.pick
          [
            ( read_line_opt context.in_channel >>= fun message_opt ->
              match message_opt with
              | Some message ->
                  (if not (String.equal message acknowledge) then
                     let from =
                       match context.side with
                       | Server_side -> "client"
                       | Client_side -> "server"
                     in
                     printf "From %s: %s\n" from message |> ignore);

                  write_line context.out_channel acknowledge
                  >>= recv_handler context
              | None -> (
                  match context.side with
                  | Server_side -> print "Connection closed.\n" >>= return
                  | Client_side -> recv_handler context ()) );
            cancel_signal;
          ]
    | Closed -> return ()
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
              | Some input ->
                  if String.equal input "]" && is_client context.side then (
                    let* () = print "Closing connection...\n" in
                    wakeup cancel_wakeup ();
                    Lwt_unix.close context.socket)
                  else
                    let rtt_start = Unix.gettimeofday () in
                    let* () = write_line context.out_channel input in
                    let* ack = read_line context.in_channel in
                    let rtt_end = Unix.gettimeofday () in
                    let rtt = rtt_end -. rtt_start in
                    printf "Ack: %s | Roundtrip Time: %fs\n" ack rtt
                    >>= send_handler context
              | None -> send_handler context () );
            cancel_signal;
          ]
    | Closed -> return ()
    | Aborted exn ->
        exn |> Printexc.to_string
        |> printf "Connection aborted with error: %s\n"
end
