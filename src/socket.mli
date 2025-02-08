open Lwt_unix

val create : unit -> file_descr
val bind : Unix.inet_addr -> int -> file_descr -> unit Lwt.t
val listen : int -> file_descr -> unit
val peername : file_descr -> string

module Protocol : sig
  type side = Server_side | Client_side

  module Context : sig
    type t = { socket : file_descr; side : side }

    val make : socket:file_descr -> side:side -> t
  end

  val recv_handler : Context.t -> unit -> unit Lwt.t
  val send_handler : Context.t -> unit -> unit Lwt.t
end
