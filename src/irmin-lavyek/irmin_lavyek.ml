open Lwt.Syntax

module Helper (K : Irmin.Type.S) (V : Irmin.Type.S) = struct
  module Tbl = Hashtbl.Make (struct
    type t = K.t

    let equal a b = Irmin.Type.(unstage (equal K.t)) a b
    let hash k = Irmin.Type.(unstage (short_hash K.t)) k
  end)

  type 'a t = V.t Tbl.t (* Store type: a hashtable mapping keys to values *)
  type key = K.t (* Key type *)
  type value = V.t (* Value type *)

  let spec = Irmin.Backend.Conf.Spec.v "fake-lavyek"
  let init_size = Irmin.Backend.Conf.key ~spec "init-size" Irmin.Type.int 8

  let v config =
    let module C = Irmin.Backend.Conf in
    let init_size = C.get config init_size in
    Lwt.return (Tbl.create init_size)

  let mem t key = Lwt.return (Tbl.mem t key)
  let find t key = Lwt.return (Tbl.find_opt t key)
  let clear t = Lwt.return (Tbl.clear t)
end

module Content_addressable : Irmin.Content_addressable.Maker =
functor
  (K : Irmin.Hash.S)
  (V : Irmin.Type.S)
  ->
  struct
    include Helper (K) (V)

    let encode_value = Irmin.Type.(unstage (to_bin_string V.t))

    let unsafe_add t k v =
      Tbl.replace t k v;
      Lwt.return_unit

    let add t value =
      let hash = K.hash (fun f -> f (encode_value value)) in
      let+ () = unsafe_add t hash value in
      print_endline (Irmin.Type.to_string K.t hash);
      hash

    let lock = Mutex.create ()

    let batch t f =
      Mutex.lock lock;
      let+ x =
        try f t
        with exn ->
          Mutex.unlock lock;
          raise exn
      in
      Mutex.unlock lock;
      x

    let close _t = Lwt.return_unit
  end

module Atomic_write : Irmin.Atomic_write.Maker =
functor
  (K : Irmin.Type.S)
  (V : Irmin.Type.S)
  ->
  struct
    module H = Helper (K) (V)
    module W = Irmin.Backend.Watch.Make (K) (V)

    type t = { t : [ `Write ] H.t; w : W.t } (* Store type *)
    type key = H.key (* Key type *)
    type value = H.value (* Value type *)
    type watch = W.watch (* Watch type *)

    let watches = W.v ()

    let v config =
      let* t = H.v config in
      Lwt.return { t; w = watches }

    let find t = H.find t.t
    let mem t = H.mem t.t
    let watch_key t key = W.watch_key t.w key
    let watch t = W.watch t.w
    let unwatch t = W.unwatch t.w

    let list { t; _ } =
      let keys = H.Tbl.to_seq_keys t |> List.of_seq in
      Lwt.return keys

    let set { t; w } key value =
      print_endline "set0";
      let exists = H.Tbl.mem t key in
      print_endline "set1";
      H.Tbl.replace t key value;
      print_endline "set2";
      if exists then W.notify w key (Some value) else Lwt.return_unit

    let remove { t; w } key =
      H.Tbl.remove t key;
      W.notify w key None

    let value_equal = Irmin.Type.(unstage (equal (option V.t)))

    let test_and_set { t; w } key ~test ~set:set_value =
      print_endline "testset0";
      let v = H.Tbl.find_opt t key in
      print_endline "testset1";
      if value_equal v test then (
        let () =
          print_endline "testset2";
          match set_value with
          | Some set_value -> H.Tbl.replace t key set_value
          | None -> H.Tbl.remove t key
        in
        print_endline "testset3";
        let* () = W.notify w key set_value in
        print_endline "testset4";
        Lwt.return_true)
      else (
        print_endline "testset5";
        Lwt.return_false)

    let clear { t; _ } =
      H.Tbl.clear t;
      Lwt.return_unit

    let close _t = Lwt.return_unit
  end

module Maker : Irmin.Maker = Irmin.Maker (Content_addressable) (Atomic_write)

module KV = struct
  type endpoint = unit
  type metadata = unit

  module Make (C : Irmin.Contents.S) = struct
    include Maker.Make (struct
      module Info = Irmin.Info.Default
      module Metadata = Irmin.Metadata.None
      module Contents = C
      module Path = Irmin.Path.String_list
      module Branch = Irmin.Branch.String
      module Hash = Irmin.Hash.SHA1
      module Node = Irmin.Node.Make (Hash) (Path) (Metadata)
      module Commit = Irmin.Commit.Make (Hash)
    end)
  end
end

module Store = KV.Make (Irmin.Contents.String)
