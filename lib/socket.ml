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

  let send socket buffer offset remaining =
    let open Lwt in
    catch
      (fun () ->
        Buffer.send socket buffer offset remaining >>= fun _ -> return (Ok ()))
      (fun exn ->
        let msg =
          match exn with
          | Canceled -> "\n"
          | _ ->
              exn |> Printexc.to_string
              |> Printf.sprintf "Unexpected error: %s\n"
        in
        Lwt_io.print msg >>= fun () -> return (Error exn))

  let read_all_opt socket =
    let open Lwt in
    let open Lwt.Syntax in
    catch
      (fun () ->
        let* len = Buffer.prefix socket in
        let msg_buf = Buffer.init len in
        Buffer.read socket msg_buf 0 len >>= fun _ ->
        Some (Buffer.to_string msg_buf) |> return)
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
         send socket buffer 0 (4 + len) >>= function
         | Ok () -> return true
         | Error _ -> return false);
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
         send socket buffer 0 (4 + len) >>= function
         | Ok () -> (
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
         | Error _ -> return false);
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
