let create () = Lwt_unix.socket PF_INET SOCK_STREAM 0
let bind address port socket = Lwt_unix.bind socket @@ ADDR_INET (address, port)

let listen max_pending_requests socket =
  Lwt_unix.listen socket max_pending_requests

let peername socket =
  match Lwt_unix.getpeername socket with
  | ADDR_INET (addr, port) ->
      Printf.sprintf "%s:%d" (Unix.string_of_inet_addr addr) port
  | _ -> ""

type side = Server_side | Client_side

module Context = struct
  type t = {
    descriptor : Lwt_unix.file_descr;
    side : side;
    cancel_thread : unit Lwt.t;
    cancel_resolver : unit Lwt.u;
  }

  let make ~descriptor ~side =
    let cancel_thread, cancel_resolver = Lwt.wait () in
    { descriptor; side; cancel_thread; cancel_resolver }

  let is_connected context =
    let open Lwt_unix in
    try
      match getpeername context.descriptor with
      | ADDR_INET _ -> true
      | ADDR_UNIX _ -> false
    with _ -> false
end

module Buffer = struct
  type t = bytes

  let prefix_length = 4
  let msg_flags = []

  let of_string message =
    let message_length = String.length message in
    let buffer = Bytes.create (prefix_length + message_length) in
    Bytes.set_int32_be buffer 0 (Int32.of_int message_length);
    Bytes.blit_string message 0 buffer prefix_length message_length;
    (message_length, buffer)

  let rec send_all socket buffer offset remaining =
    let open Lwt in
    if remaining = 0 then return ()
    else
      Lwt_unix.send socket buffer offset remaining msg_flags
      >>= fun bytes_sent ->
      send_all socket buffer (offset + bytes_sent) (remaining - bytes_sent)

  let rec read_all socket buffer offset remaining =
    let open Lwt in
    if remaining = 0 then return ()
    else
      Lwt_unix.recv socket buffer offset remaining msg_flags
      >>= fun bytes_read ->
      if bytes_read = 0 && remaining <> 0 then fail End_of_file
      else read_all socket buffer (offset + bytes_read) (remaining - bytes_read)
end

module Protocol = struct
  let acknowledge = "Message received"

  let safe_shutdown socket =
    let open Lwt in
    catch
      (fun () ->
        Lwt_unix.shutdown socket SHUTDOWN_SEND;
        Lwt_unix.shutdown socket SHUTDOWN_RECEIVE |> return)
      (function
        | Unix.Unix_error (Unix.ENOTCONN, _, _) -> return () | exn -> fail exn)

  let safe_close socket =
    let open Lwt in
    catch
      (fun () -> safe_shutdown socket >>= fun () -> Lwt_unix.close socket)
      (function
        | Unix.Unix_error (Unix.EBADF, _, _) -> return () | exn -> fail exn)

  let send_all_opt socket buffer offset remaining =
    let open Lwt in
    catch
      (fun () ->
        Buffer.send_all socket buffer offset remaining >>= fun _ ->
        return (Some ()))
      (fun exn ->
        let msg =
          match exn with
          | Canceled -> "\n"
          | _ ->
              exn |> Printexc.to_string
              |> Printf.sprintf "Unexpected error: %s\n"
        in
        Lwt_io.print msg >>= fun () -> return None)

  let read_all_opt socket =
    let open Lwt in
    catch
      (fun () ->
        let len_buf = Bytes.create 4 in
        Buffer.read_all socket len_buf 0 4 >>= fun _ ->
        let len = Bytes.get_int32_be len_buf 0 |> Int32.to_int in
        let msg_buf = Bytes.create len in
        Buffer.read_all socket msg_buf 0 len >>= fun _ ->
        Some (Bytes.to_string msg_buf) |> return)
      (fun exn ->
        let msg =
          match exn with
          | Unix.Unix_error (Unix.ECONNRESET, _, _) | End_of_file ->
              Printf.sprintf "Connection closed with %s\n" (peername socket)
          (* Workaround *)
          | Unix.Unix_error (Unix.EBADF, _, _) | Canceled -> ""
          | _ ->
              exn |> Printexc.to_string
              |> Printf.sprintf "Unexpected error: %s\n"
        in
        Lwt_io.print msg >>= fun () -> return None)

  let send_ack socket =
    let open Lwt in
    pick
      [
        (let len, buffer = Buffer.of_string acknowledge in
         send_all_opt socket buffer 0 (4 + len) >>= function
         | Some () -> return true
         | None -> return false);
        ( Lwt_unix.timeout 5.0 >>= fun () ->
          Lwt_io.printf
            "Sending acknowledgement reached timeout! Closing connection.\n"
          >>= fun () -> return false );
      ]

  let send_and_wait_ack socket message =
    let open Lwt in
    pick
      [
        (let len, buffer = Buffer.of_string message in
         let rtt_start = Unix.gettimeofday () in
         send_all_opt socket buffer 0 (4 + len) >>= function
         | Some () -> (
             read_all_opt socket >>= fun ack_opt ->
             match ack_opt with
             | Some ack ->
                 let rtt_end = Unix.gettimeofday () in
                 let rtt = rtt_end -. rtt_start in
                 Lwt_io.printf "Ack: %s | Roundtrip Time: %fs\n" ack rtt
                 >>= fun () -> return true
             | None ->
                 Lwt_io.print "Acknowledgement not received.\n" >>= fun () ->
                 return false)
         | None -> return false);
        ( Lwt_unix.timeout 5.0 >>= fun () ->
          Lwt_io.printf "Sending message reached timeout! Closing connection.\n"
          >>= fun () -> return false );
      ]

  let recv_handler context () =
    let open Lwt in
    let open Context in
    let rec loop context () =
      match (is_connected context, Lwt_unix.state context.descriptor) with
      | true, Opened -> (
          read_all_opt context.descriptor >>= fun message_opt ->
          match message_opt with
          | Some message -> (
              (if not (String.equal message acknowledge) then
                 let from =
                   match context.side with
                   | Server_side -> "client"
                   | Client_side -> "server"
                 in
                 Lwt_io.printf "From %s: %s\n" from message |> ignore);
              send_ack context.descriptor >>= function
              | true -> loop context ()
              | false -> return ())
          | None ->
              wakeup context.cancel_resolver ();
              safe_close context.descriptor >>= return)
      | false, _ | _, Closed -> return ()
      | _, Aborted exn ->
          exn |> Printexc.to_string
          |> Lwt_io.printf "Connection aborted with error: %s"
    in
    pick [ loop context (); context.cancel_thread ]

  let is_client = function Client_side -> true | _ -> false

  let send_handler context () =
    let open Lwt in
    let open Context in
    let rec loop context () =
      match (is_connected context, Lwt_unix.state context.descriptor) with
      | true, Opened -> (
          Lwt_io.read_line_opt Lwt_io.stdin >>= fun message_opt ->
          match message_opt with
          | Some input -> (
              match (input, is_client context.side) with
              | "]", true ->
                  Lwt_io.print "Closing connection...\n" >>= fun () ->
                  wakeup context.cancel_resolver ();
                  safe_close context.descriptor
              | _, _ -> (
                  send_and_wait_ack context.descriptor input >>= function
                  | true -> loop context ()
                  | false -> return ()))
          | None -> loop context ())
      | false, _ | _, Closed -> return ()
      | _, Aborted exn ->
          exn |> Printexc.to_string
          |> Lwt_io.printf "Connection aborted with error: %s\n"
    in
    pick [ loop context (); context.cancel_thread ]
end
