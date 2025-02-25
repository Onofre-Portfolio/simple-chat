type t = bytes

val init : int -> t
val of_string : string -> int * t
val to_string : t -> string
val send : Lwt_unix.file_descr -> t -> int -> int -> unit Lwt.t
val read : Lwt_unix.file_descr -> t -> int -> int -> unit Lwt.t
val prefix : Lwt_unix.file_descr -> int Lwt.t
