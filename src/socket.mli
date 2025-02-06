type side = Server_side | Client_side

val create : unit -> Lwt_unix.file_descr
val bind : Unix.inet_addr -> int -> Lwt_unix.file_descr -> unit
val listen : int -> Lwt_unix.file_descr -> unit

module Protocol : sig
  val recv_handler :
    side -> Lwt_io.input_channel -> Lwt_io.output_channel -> unit -> unit Lwt.t

  val send_handler :
    side ->
    Lwt_unix.file_descr ->
    Lwt_io.input_channel ->
    Lwt_io.output_channel ->
    unit ->
    unit Lwt.t
end
