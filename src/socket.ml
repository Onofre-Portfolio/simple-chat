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

  let buffer_of_string msg =
    let len = String.length msg in
    let buffer = Bytes.create (4 + len) in
    Bytes.set_int32_be buffer 0 (Int32.of_int len);
    Bytes.blit_string msg 0 buffer 4 len;
    (len, buffer)

  let rec send_all socket buffer offset remaining =
    if remaining = 0 then return ()
    else
      let* bytes_sent =
        Lwt_unix.send socket buffer offset remaining msg_flags
      in
      send_all socket buffer (offset + bytes_sent) (remaining - bytes_sent)

  let rec read_all socket buffer offset remaining =
    if remaining = 0 then return ()
    else
      let* bytes_read =
        Lwt_unix.recv socket buffer offset remaining msg_flags
      in
      if bytes_read = 0 && remaining <> 0 then Lwt.fail End_of_file
      else read_all socket buffer (offset + bytes_read) (remaining - bytes_read)

  let send_all_opt socket buffer offset remaining =
    catch
      (fun () ->
        send_all socket buffer offset remaining >>= fun _ -> return (Some ()))
      (fun exn ->
        let msg =
          match exn with
          | Canceled -> ""
          | _ ->
              exn |> Printexc.to_string |> Printf.sprintf "Unexpected error: %s"
        in
        printf "%s\n" msg >>= fun () -> return None)

  let read_all_opt socket =
    catch
      (fun () ->
        let len_buf = Bytes.create 4 in
        let* _ = read_all socket len_buf 0 4 in
        let len = Bytes.get_int32_be len_buf 0 |> Int32.to_int in
        let msg_buf = Bytes.create len in
        let* _ = read_all socket msg_buf 0 len in
        Some (Bytes.to_string msg_buf) |> return)
      (fun exn ->
        let msg =
          match exn with
          | Unix.Unix_error (Unix.ECONNRESET, _, _) | End_of_file ->
              Printf.sprintf "Connection closed with %s" (peername socket)
          | Canceled -> ""
          | _ ->
              exn |> Printexc.to_string |> Printf.sprintf "Unexpected error: %s"
        in
        printf "%s\n" msg >>= fun () -> return None)

  let safe_shutdown socket =
    catch
      (fun () -> shutdown socket SHUTDOWN_SEND |> return)
      (function
        | Unix.Unix_error (Unix.ENOTCONN, _, _) -> return ()
        | exn -> Lwt.fail exn)

  let rec recv_handler context () =
    let open Context in
    match state context.socket with
    | Opened ->
        Lwt.pick
          [
            ( read_all_opt context.socket >>= fun message_opt ->
              match message_opt with
              | Some message -> (
                  (if not (String.equal message acknowledge) then
                     let from =
                       match context.side with
                       | Server_side -> "client"
                       | Client_side -> "server"
                     in
                     printf "From %s: %s\n" from message |> ignore);
                  let len, buffer = buffer_of_string acknowledge in
                  send_all_opt context.socket buffer 0 (4 + len) >>= function
                  | Some () -> recv_handler context ()
                  | None -> return ())
              | None -> (
                  match context.side with
                  | Client_side ->
                      wakeup cancel_wakeup ();
                      Lwt_unix.close context.socket >>= return
                  | Server_side -> Lwt_unix.close context.socket >>= return) );
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
                  match (input, is_client context.side) with
                  | "]", true ->
                      let* () = print "Closing connection...\n" in
                      wakeup cancel_wakeup ();
                      safe_shutdown context.socket >>= fun () ->
                      Lwt_unix.close context.socket
                  | _, _ -> (
                      let len, buffer = buffer_of_string input in
                      let rtt_start = Unix.gettimeofday () in
                      send_all_opt context.socket buffer 0 (4 + len)
                      >>= function
                      | Some () -> (
                          let* ack_opt = read_all_opt context.socket in
                          match ack_opt with
                          | Some ack ->
                              let rtt_end = Unix.gettimeofday () in
                              let rtt = rtt_end -. rtt_start in
                              printf "Ack: %s | Roundtrip Time: %fs\n" ack rtt
                              >>= send_handler context
                          | None ->
                              print "Acknowledgement not received! Try again.\n"
                              >>= send_handler context)
                      | None -> return ()))
              | None -> send_handler context () );
            cancel_signal;
          ]
    | Closed -> return ()
    | Aborted exn ->
        exn |> Printexc.to_string
        |> printf "Connection aborted with error: %s\n"
end
