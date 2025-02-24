val create : unit -> Lwt_unix.file_descr
val bind : Unix.inet_addr -> int -> Lwt_unix.file_descr -> unit Lwt.t
val listen : int -> Lwt_unix.file_descr -> unit
val peername : Lwt_unix.file_descr -> string

type side = Server_side | Client_side

module Context : sig
  type t = {
    descriptor : Lwt_unix.file_descr;
    side : side;
    cancel_thread : unit Lwt.t;
    cancel_resolver : unit Lwt.u;
  }

  val make : descriptor:Lwt_unix.file_descr -> side:side -> t
end

module Protocol : sig
  val safe_close : Lwt_unix.file_descr -> unit Lwt.t
  val recv_handler : Context.t -> unit -> unit Lwt.t
  val send_handler : Context.t -> unit -> unit Lwt.t
end
