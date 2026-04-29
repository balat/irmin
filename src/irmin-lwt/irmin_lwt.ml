(* Lwt compatibility layer for Irmin 4.

   Every wrapped operation threads its call through [Lwt_eio.run_eio] so
   the direct-style Irmin 4 implementation executes on the Eio
   scheduler while the caller remains in the Lwt monad. *)

let run_eio f = Lwt_eio.run_eio f

let run f =
  Eio_main.run @@ fun env ->
  Lwt_eio.with_event_loop ~clock:env#clock @@ fun _ ->
  Lwt_eio.Promise.await_lwt (f ())

let run_with_env env f =
  Lwt_eio.with_event_loop ~clock:env#clock @@ fun _ ->
  Lwt_eio.Promise.await_lwt (f ())

module type Closeable = sig
  type 'a t

  val close : 'a t -> unit Lwt.t
end

module type Lwt_indexable_S = sig
  type -'a t
  type key
  type value
  type hash

  val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
  val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
  val close : 'a t -> unit Lwt.t
  val add : [> Irmin.Perms.write ] t -> value -> key Lwt.t
  val unsafe_add : [> Irmin.Perms.write ] t -> hash -> value -> key Lwt.t
  val index : [> Irmin.Perms.read ] t -> hash -> key option Lwt.t

  val batch :
    Irmin.Perms.read t ->
    ([ Irmin.Perms.read | Irmin.Perms.write ] t -> 'a Lwt.t) ->
    'a Lwt.t

  val merge :
    [ Irmin.Perms.read | Irmin.Perms.write ] t -> key option Irmin.Merge.t

  module Key : Irmin.Key.S with type t = key and type hash = hash
end

module type Lwt_atomic_write_S = sig
  type t
  type key
  type value
  type watch

  val mem : t -> key -> bool Lwt.t
  val find : t -> key -> value option Lwt.t
  val close : t -> unit Lwt.t
  val list : t -> key list Lwt.t
  val set : t -> key -> value -> unit Lwt.t

  val test_and_set :
    t -> key -> test:value option -> set:value option -> bool Lwt.t

  val remove : t -> key -> unit Lwt.t
  val clear : t -> unit Lwt.t

  val watch :
    t ->
    ?init:(key * value) list ->
    (key -> value Irmin.Diff.t -> unit Lwt.t) ->
    watch Lwt.t

  val watch_key :
    t -> key -> ?init:value -> (value Irmin.Diff.t -> unit Lwt.t) -> watch Lwt.t

  val unwatch : t -> watch -> unit Lwt.t
end

module type Lwt_node_graph_S = sig
  type 'a t
  type metadata
  type contents_key
  type node_key
  type step
  type path
  type value = [ `Node of node_key | `Contents of contents_key * metadata ]

  val value_t : value Irmin.Type.t
  val empty : [> Irmin.Perms.write ] t -> node_key Lwt.t
  val v : [> Irmin.Perms.write ] t -> (step * value) list -> node_key Lwt.t
  val list : [> Irmin.Perms.read ] t -> node_key -> (step * value) list Lwt.t
  val find : [> Irmin.Perms.read ] t -> node_key -> path -> value option Lwt.t

  val add :
    [> Irmin.Perms.read_write ] t -> node_key -> path -> value -> node_key Lwt.t

  val remove :
    [> Irmin.Perms.read_write ] t -> node_key -> path -> node_key Lwt.t

  val closure :
    [> Irmin.Perms.read ] t ->
    min:node_key list ->
    max:node_key list ->
    node_key list Lwt.t

  val iter :
    [> Irmin.Perms.read ] t ->
    min:node_key list ->
    max:node_key list ->
    ?node:(node_key -> unit Lwt.t) ->
    ?contents:(contents_key -> unit Lwt.t) ->
    ?edge:(node_key -> node_key -> unit Lwt.t) ->
    ?skip_node:(node_key -> bool Lwt.t) ->
    ?skip_contents:(contents_key -> bool Lwt.t) ->
    ?rev:bool ->
    unit ->
    unit Lwt.t
end

module type Lwt_commit_history_S = sig
  type 'a t
  type node_key
  type commit_key
  type v
  type info

  val v :
    [> Irmin.Perms.write ] t ->
    node:node_key ->
    parents:commit_key list ->
    info:info ->
    (commit_key * v) Lwt.t

  val parents : [> Irmin.Perms.read ] t -> commit_key -> commit_key list Lwt.t

  val merge :
    [> Irmin.Perms.read_write ] t ->
    info:(unit -> info) ->
    commit_key Irmin.Merge.t

  val lcas :
    [> Irmin.Perms.read ] t ->
    ?max_depth:int ->
    ?n:int ->
    commit_key ->
    commit_key ->
    (commit_key list, [ `Max_depth_reached | `Too_many_lcas ]) result Lwt.t

  val lca :
    [> Irmin.Perms.read_write ] t ->
    info:(unit -> info) ->
    ?max_depth:int ->
    ?n:int ->
    commit_key list ->
    (commit_key option, Irmin.Merge.conflict) result Lwt.t

  val three_way_merge :
    [> Irmin.Perms.read_write ] t ->
    info:(unit -> info) ->
    ?max_depth:int ->
    ?n:int ->
    commit_key ->
    commit_key ->
    (commit_key, Irmin.Merge.conflict) result Lwt.t

  val closure :
    [> Irmin.Perms.read ] t ->
    min:commit_key list ->
    max:commit_key list ->
    commit_key list Lwt.t

  val iter :
    [> Irmin.Perms.read ] t ->
    min:commit_key list ->
    max:commit_key list ->
    ?commit:(commit_key -> unit Lwt.t) ->
    ?edge:(commit_key -> commit_key -> unit Lwt.t) ->
    ?skip:(commit_key -> bool Lwt.t) ->
    ?rev:bool ->
    unit ->
    unit Lwt.t
end

module type S = sig
  (** {1 Schema} *)

  module Schema : Irmin.Schema.S

  (** {1 Types} *)

  type repo
  type t
  type step = Schema.Path.step
  type path = Schema.Path.t
  type metadata = Schema.Metadata.t
  type contents = Schema.Contents.t
  type node
  type tree
  type commit
  type branch = Schema.Branch.t
  type slice
  type info = Schema.Info.t
  type hash = Schema.Hash.t
  type contents_key
  type node_key
  type commit_key
  type lca_error = [ `Max_depth_reached | `Too_many_lcas ]
  type ff_error = [ `No_change | `Rejected | lca_error ]

  type write_error =
    [ Irmin.Merge.conflict
    | `Too_many_retries of int
    | `Test_was of tree option ]

  type kinded_key = [ `Contents of contents_key | `Node of node_key ]
  type watch

  (** {1 Type-level submodules} *)

  module Info : Irmin.Info.S with type t = info
  module Hash : Irmin.Hash.S with type t = hash
  module Path : Irmin.Path.S with type t = path and type step = step
  module Metadata : Irmin.Metadata.S with type t = metadata

  module Backend : sig
    module Schema = Schema
    module Hash : Irmin.Hash.S with type t = Schema.Hash.t

    module Contents : sig
      include
        Lwt_indexable_S
          with type key = contents_key
           and type hash = Schema.Hash.t
           and type value = Schema.Contents.t

      module Val : Irmin.Contents.S with type t = value

      module Hash :
        Irmin.Hash.Typed with type t = Schema.Hash.t and type value = value
    end

    module Node : sig
      include
        Lwt_indexable_S with type key = node_key and type hash = Schema.Hash.t

      module Path : Irmin.Path.S with type t = path and type step = step
      module Metadata : Irmin.Metadata.S with type t = metadata

      module Val :
        Irmin.Node.Generic_key.S
          with type t = value
           and type hash = Schema.Hash.t
           and type contents_key = contents_key
           and type node_key = key
           and type metadata = metadata
           and type step = step

      module Hash :
        Irmin.Hash.Typed with type t = Schema.Hash.t and type value = value

      module Contents : module type of Contents with type key = contents_key
    end

    module Node_portable :
      Irmin.Node.Portable.S
        with type node := Node.value
         and type hash := Schema.Hash.t
         and type metadata := metadata
         and type step := step

    module Commit : sig
      include
        Lwt_indexable_S with type key = commit_key and type hash = Schema.Hash.t

      module Info : Irmin.Info.S with type t = info

      module Val :
        Irmin.Commit.Generic_key.S
          with type t = value
           and type commit_key = key
           and module Info := Schema.Info

      module Hash :
        Irmin.Hash.Typed with type t = Schema.Hash.t and type value = value

      module Node : module type of Node with type key = node_key

      val merge :
        [> Irmin.Perms.read_write ] t -> info:Info.f -> key option Irmin.Merge.t
    end

    module Commit_portable :
      Irmin.Commit.Portable.S
        with type commit := Commit.value
         and type hash := Schema.Hash.t
         and module Info = Schema.Info

    module Branch : sig
      include
        Lwt_atomic_write_S with type key = branch and type value = commit_key

      module Key : Irmin.Branch.S with type t = key
      module Val : Irmin.Key.S with type t = value
    end

    module Slice :
      Irmin.Backend.Slice.S
        with type t = slice
         and type contents = Schema.Hash.t * Schema.Contents.t
         and type node = Schema.Hash.t * Node.value
         and type commit = Schema.Hash.t * Commit.value

    module Repo : sig
      type nonrec t = repo

      val v : Irmin.Backend.Conf.t -> t Lwt.t
      val close : t -> unit Lwt.t
      val contents_t : t -> Irmin.Perms.read Contents.t
      val node_t : t -> Irmin.Perms.read Node.t
      val commit_t : t -> Irmin.Perms.read Commit.t
      val config : t -> Irmin.Backend.Conf.t

      val batch :
        ?lock:bool ->
        t ->
        (Irmin.Perms.read_write Contents.t ->
        Irmin.Perms.read_write Node.t ->
        Irmin.Perms.read_write Commit.t ->
        'a Lwt.t) ->
        'a Lwt.t

      val branch_t : t -> Branch.t
    end

    module Remote : sig
      type t
      type endpoint
      type nonrec commit = commit_key
      type nonrec branch = branch

      val fetch :
        t ->
        ?depth:int ->
        endpoint ->
        branch ->
        (commit option, [ `Msg of string ]) result Lwt.t

      val push :
        t ->
        ?depth:int ->
        endpoint ->
        branch ->
        (unit, [ `Msg of string | `Detached_head ]) result Lwt.t

      val v : Repo.t -> t
    end
  end

  (** {1 Underlying direct-style store}

      The Irmin 4 direct-style store this Lwt-flavoured shim wraps. *)
  module Underlying :
    Irmin.Generic_key.S
      with module Schema = Schema
       and type repo = repo
       and type t = t
       and type node = node
       and type tree = tree
       and type commit = commit
       and type slice = slice
       and type contents_key = contents_key
       and type node_key = node_key
       and type commit_key = commit_key
       and type Schema.Hash.t = hash
       and type 'a Backend.Contents.t = 'a Backend.Contents.t
       and type 'a Backend.Node.t = 'a Backend.Node.t
       and type 'a Backend.Commit.t = 'a Backend.Commit.t
       and type Backend.Branch.t = Backend.Branch.t

  module Contents : sig
    include Irmin.Contents.S with type t = contents

    val hash : contents -> hash
    val of_key : repo -> contents_key -> contents option Lwt.t
    val of_hash : repo -> hash -> contents option Lwt.t
  end

  module History : Graph.Sig.P with type V.t = commit

  module Status : sig
    type t = [ `Empty | `Branch of branch | `Commit of commit ]

    val t : repo -> t Irmin.Type.t
    val pp : t Fmt.t
  end

  type Irmin.remote +=
    | E of Backend.Remote.endpoint
          (** Extends [Irmin.remote] with the endpoint type of [Backend]. *)

  (** {1 Repositories} *)

  module Repo : sig
    type nonrec t = repo

    type elt =
      [ `Commit of commit_key
      | `Node of node_key
      | `Contents of contents_key
      | `Branch of branch ]

    val elt_t : elt Irmin.Type.t
    val v : Irmin.Backend.Conf.t -> t Lwt.t

    include Closeable with type _ t := t

    val heads : t -> commit list Lwt.t
    val branches : t -> branch list Lwt.t
    val config : t -> Irmin.Backend.Conf.t

    val export :
      ?full:bool ->
      ?depth:int ->
      ?min:commit list ->
      ?max:[ `Head | `Max of commit list ] ->
      t ->
      slice Lwt.t

    val import : t -> slice -> (unit, [ `Msg of string ]) result Lwt.t
    val default_pred_commit : t -> commit_key -> elt list Lwt.t
    val default_pred_node : t -> node_key -> elt list Lwt.t
    val default_pred_contents : t -> contents_key -> elt list Lwt.t

    val iter :
      ?cache_size:int ->
      min:elt list ->
      max:elt list ->
      ?edge:(elt -> elt -> unit Lwt.t) ->
      ?branch:(branch -> unit Lwt.t) ->
      ?commit:(commit_key -> unit Lwt.t) ->
      ?node:(node_key -> unit Lwt.t) ->
      ?contents:(contents_key -> unit Lwt.t) ->
      ?skip_branch:(branch -> bool Lwt.t) ->
      ?skip_commit:(commit_key -> bool Lwt.t) ->
      ?skip_node:(node_key -> bool Lwt.t) ->
      ?skip_contents:(contents_key -> bool Lwt.t) ->
      ?pred_branch:(t -> branch -> elt list Lwt.t) ->
      ?pred_commit:(t -> commit_key -> elt list Lwt.t) ->
      ?pred_node:(t -> node_key -> elt list Lwt.t) ->
      ?pred_contents:(t -> contents_key -> elt list Lwt.t) ->
      ?rev:bool ->
      t ->
      unit Lwt.t

    val breadth_first_traversal :
      ?cache_size:int ->
      max:elt list ->
      ?branch:(branch -> unit Lwt.t) ->
      ?commit:(commit_key -> unit Lwt.t) ->
      ?node:(node_key -> unit Lwt.t) ->
      ?contents:(contents_key -> unit Lwt.t) ->
      ?pred_branch:(t -> branch -> elt list Lwt.t) ->
      ?pred_commit:(t -> commit_key -> elt list Lwt.t) ->
      ?pred_node:(t -> node_key -> elt list Lwt.t) ->
      ?pred_contents:(t -> contents_key -> elt list Lwt.t) ->
      t ->
      unit Lwt.t
  end

  (** {1 Stores} *)

  val main : repo -> t Lwt.t

  val master : repo -> t Lwt.t
  [@@ocaml.deprecated "Use `main` instead."]
  (** Deprecated alias kept for Irmin 3 compatibility. Use {!main}. *)

  val of_branch : repo -> branch -> t Lwt.t
  val of_commit : commit -> t Lwt.t
  val empty : repo -> t Lwt.t
  val repo : t -> repo
  val tree : t -> tree Lwt.t
  val status : t -> [ `Empty | `Branch of branch | `Commit of commit ]

  (** {2 Reads} *)

  val find : t -> path -> contents option Lwt.t
  val find_all : t -> path -> (contents * metadata) option Lwt.t
  val mem : t -> path -> bool Lwt.t
  val mem_tree : t -> path -> bool Lwt.t
  val get : t -> path -> contents Lwt.t
  val get_all : t -> path -> (contents * metadata) Lwt.t
  val find_tree : t -> path -> tree option Lwt.t
  val get_tree : t -> path -> tree Lwt.t
  val hash : t -> path -> hash option Lwt.t
  val kind : t -> path -> [ `Contents | `Node ] option Lwt.t
  val list : t -> path -> (step * tree) list Lwt.t
  val key : t -> path -> kinded_key option Lwt.t

  (** {2 Writes} *)

  val set :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    contents ->
    (unit, write_error) result Lwt.t

  val set_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    contents ->
    unit Lwt.t

  val set_tree :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    tree ->
    (unit, write_error) result Lwt.t

  val set_tree_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    tree ->
    unit Lwt.t

  val remove :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    (unit, write_error) result Lwt.t

  val remove_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    unit Lwt.t

  val test_and_set :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:contents option ->
    set:contents option ->
    (unit, write_error) result Lwt.t

  val test_and_set_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:contents option ->
    set:contents option ->
    unit Lwt.t

  val test_and_set_tree :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:tree option ->
    set:tree option ->
    (unit, write_error) result Lwt.t

  val test_and_set_tree_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:tree option ->
    set:tree option ->
    unit Lwt.t

  val test_set_and_get :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:contents option ->
    set:contents option ->
    (commit option, write_error) result Lwt.t

  val test_set_and_get_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:contents option ->
    set:contents option ->
    commit option Lwt.t

  val test_set_and_get_tree :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:tree option ->
    set:tree option ->
    (commit option, write_error) result Lwt.t

  val test_set_and_get_tree_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:tree option ->
    set:tree option ->
    commit option Lwt.t

  val merge :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:contents option ->
    t ->
    path ->
    contents option ->
    (unit, write_error) result Lwt.t

  val merge_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:contents option ->
    t ->
    path ->
    contents option ->
    unit Lwt.t

  val merge_tree :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:tree option ->
    t ->
    path ->
    tree option ->
    (unit, write_error) result Lwt.t

  val merge_tree_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:tree option ->
    t ->
    path ->
    tree option ->
    unit Lwt.t

  val with_tree :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    ?strategy:[ `Set | `Test_and_set | `Merge ] ->
    info:Info.f ->
    t ->
    path ->
    (tree option -> tree option) ->
    (unit, write_error) result Lwt.t

  val with_tree_exn :
    ?clear:bool ->
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    ?strategy:[ `Set | `Test_and_set | `Merge ] ->
    info:Info.f ->
    t ->
    path ->
    (tree option -> tree option) ->
    unit Lwt.t

  val clone : src:t -> dst:branch -> t Lwt.t

  (** {2 Merges and ancestors} *)

  type 'a merge =
    info:Info.f ->
    ?max_depth:int ->
    ?n:int ->
    'a ->
    (unit, Irmin.Merge.conflict) result Lwt.t
  (** Lwt-wrapped abbreviation for merge-into-something functions. *)

  val merge_into : into:t -> t merge
  val merge_with_branch : t -> branch merge
  val merge_with_commit : t -> commit merge

  val lcas :
    ?max_depth:int -> ?n:int -> t -> t -> (commit list, lca_error) result Lwt.t

  val lcas_with_branch :
    t ->
    ?max_depth:int ->
    ?n:int ->
    branch ->
    (commit list, lca_error) result Lwt.t

  val lcas_with_commit :
    t ->
    ?max_depth:int ->
    ?n:int ->
    commit ->
    (commit list, lca_error) result Lwt.t

  val history :
    ?depth:int -> ?min:commit list -> ?max:commit list -> t -> History.t Lwt.t

  val last_modified : ?depth:int -> ?n:int -> t -> path -> commit list Lwt.t

  (** {2 Backend converters} *)

  val of_backend_node : repo -> Backend.Node.value -> node
  val to_backend_node : node -> Backend.Node.value Lwt.t
  val to_backend_portable_node : node -> Backend.Node_portable.t Lwt.t
  val to_backend_commit : commit -> Backend.Commit.value

  val of_backend_commit :
    repo -> Backend.Commit.Key.t -> Backend.Commit.value -> commit

  val save_contents :
    [> Irmin.Perms.write ] Backend.Contents.t -> contents -> contents_key Lwt.t

  val save_tree :
    ?clear:bool ->
    repo ->
    [> Irmin.Perms.write ] Backend.Contents.t ->
    [> Irmin.Perms.read_write ] Backend.Node.t ->
    tree ->
    kinded_key Lwt.t

  (** {1 Trees} *)

  module Tree : sig
    type nonrec t = tree
    type kinded_hash = [ `Contents of hash * metadata | `Node of hash ]

    type kinded_key =
      [ `Contents of contents_key * metadata | `Node of node_key ]

    type elt = [ `Node of node | `Contents of contents * metadata ]
    type marks

    type depth =
      [ `Eq of int | `Le of int | `Lt of int | `Ge of int | `Gt of int ]

    type stats

    val kinded_key_t : kinded_key Irmin.Type.t
    val stats_t : stats Irmin.Type.t

    type concrete =
      [ `Tree of (step * concrete) list | `Contents of contents * metadata ]

    type 'a force = [ `True | `False of path -> 'a -> 'a Lwt.t ]
    type uniq = [ `False | `True | `Marks of marks ]
    type ('a, 'b) folder = path -> 'b -> 'a -> 'a Lwt.t

    type error =
      [ `Dangling_hash of hash | `Pruned_hash of hash | `Portable_value ]

    type 'a or_error = ('a, error) result

    exception Dangling_hash of { context : string; hash : hash }
    exception Pruned_hash of { context : string; hash : hash }
    exception Portable_value of { context : string }

    (** Operations on lazy tree contents. *)
    module Contents : sig
      type nonrec t

      val hash : ?cache:bool -> t -> hash
      val key : t -> contents_key option
      val force : t -> contents or_error Lwt.t
      val force_exn : t -> contents Lwt.t
      val clear : t -> unit
    end

    val empty : unit -> t
    val singleton : path -> ?metadata:metadata -> contents -> t
    val of_contents : ?metadata:metadata -> contents -> t
    val of_node : node -> t
    val v : elt -> t
    val pruned : kinded_hash -> t
    val is_empty : t -> bool
    val destruct : t -> [ `Node of node | `Contents of Contents.t * metadata ]
    val hash : ?cache:bool -> t -> hash
    val kinded_hash : ?cache:bool -> t -> kinded_hash
    val key : t -> kinded_key option
    val shallow : Repo.t -> kinded_key -> t
    val clear : ?depth:int -> t -> unit
    val pp : t Irmin.Type.pp
    val kind : t -> path -> [ `Contents | `Node ] option Lwt.t
    val diff : t -> t -> (path * (contents * metadata) Irmin.Diff.t) list Lwt.t
    val mem : t -> path -> bool Lwt.t
    val find_all : t -> path -> (contents * metadata) option Lwt.t
    val length : t -> ?cache:bool -> path -> int Lwt.t
    val find : t -> path -> contents option Lwt.t
    val get_all : t -> path -> (contents * metadata) Lwt.t
    val get : t -> path -> contents Lwt.t

    val list :
      t ->
      ?offset:int ->
      ?length:int ->
      ?cache:bool ->
      path ->
      (step * t) list Lwt.t

    val seq :
      t ->
      ?offset:int ->
      ?length:int ->
      ?cache:bool ->
      path ->
      (step * t) Seq.t Lwt.t

    val add : t -> path -> ?metadata:metadata -> contents -> t Lwt.t

    val update :
      t ->
      path ->
      ?metadata:metadata ->
      (contents option -> contents option) ->
      t Lwt.t

    val remove : t -> path -> t Lwt.t
    val mem_tree : t -> path -> bool Lwt.t
    val find_tree : t -> path -> t option Lwt.t
    val get_tree : t -> path -> t Lwt.t
    val add_tree : t -> path -> t -> t Lwt.t
    val update_tree : t -> path -> (t option -> t option) -> t Lwt.t
    val of_concrete : concrete -> t
    val stats : ?force:bool -> t -> stats Lwt.t
    val to_concrete : t -> concrete Lwt.t
    val find_key : Repo.t -> t -> kinded_key option Lwt.t
    val of_key : Repo.t -> kinded_key -> t option Lwt.t
    val of_hash : Repo.t -> kinded_hash -> t option Lwt.t

    (** {2 Fold} *)

    val empty_marks : unit -> marks

    val fold :
      ?order:[ `Sorted | `Undefined | `Random of Random.State.t ] ->
      ?force:'a force ->
      ?cache:bool ->
      ?uniq:uniq ->
      ?pre:('a, step list) folder ->
      ?post:('a, step list) folder ->
      ?depth:depth ->
      ?contents:('a, contents) folder ->
      ?node:('a, node) folder ->
      ?tree:('a, t) folder ->
      t ->
      'a ->
      'a Lwt.t

    val merge : t Irmin.Merge.t

    type counters

    val counters : unit -> counters
    val dump_counters : unit Fmt.t
    val reset_counters : unit -> unit

    val inspect :
      t ->
      [ `Contents
      | `Node of [ `Map | `Key | `Value | `Portable_dirty | `Pruned ] ]

    module Proof : sig
      type 'a inode = { length : int; proofs : (int * 'a) list }
      type 'a inode_extender = { length : int; segments : int list; proof : 'a }

      type tree =
        | Contents of contents * metadata
        | Blinded_contents of hash * metadata
        | Node of (step * tree) list
        | Blinded_node of hash
        | Inode of inode_tree inode
        | Extender of inode_tree inode_extender

      and inode_tree =
        | Blinded_inode of hash
        | Inode_values of (step * tree) list
        | Inode_tree of inode_tree inode
        | Inode_extender of inode_tree inode_extender

      type t

      val v : before:kinded_hash -> after:kinded_hash -> tree -> t
      val before : t -> kinded_hash
      val after : t -> kinded_hash
      val state : t -> tree

      type irmin_tree

      val to_tree : t -> irmin_tree
    end
    with type irmin_tree := t

    type verifier_error = [ `Proof_mismatch of string ]

    val produce_proof :
      Repo.t -> kinded_key -> (t -> (t * 'a) Lwt.t) -> (Proof.t * 'a) Lwt.t

    val verify_proof :
      Proof.t -> (t -> (t * 'a) Lwt.t) -> (t * 'a, verifier_error) result Lwt.t

    val hash_of_proof_state : Proof.tree -> kinded_hash
  end

  (** {1 Commits} *)

  module Commit : sig
    type nonrec t = commit
    type nonrec commit_key = commit_key

    val tree : t -> tree
    val parents : t -> commit_key list
    val info : t -> info
    val hash : t -> hash
    val key : t -> commit_key
    val pp : t Fmt.t
    val pp_hash : t Fmt.t

    val v :
      ?clear:bool ->
      Repo.t ->
      info:info ->
      parents:commit_key list ->
      tree ->
      t Lwt.t

    val of_key : Repo.t -> commit_key -> t option Lwt.t
    val of_hash : Repo.t -> hash -> t option Lwt.t
  end

  (** {1 Branches} *)

  module Branch : sig
    type nonrec t = branch

    val mem : Repo.t -> t -> bool Lwt.t
    val find : Repo.t -> t -> commit option Lwt.t
    val get : Repo.t -> t -> commit Lwt.t
    val set : Repo.t -> t -> commit -> unit Lwt.t
    val remove : Repo.t -> t -> unit Lwt.t
    val list : Repo.t -> t list Lwt.t
    val pp : t Fmt.t

    val watch :
      Repo.t ->
      t ->
      ?init:commit ->
      (commit Irmin.Diff.t -> unit Lwt.t) ->
      watch Lwt.t

    val watch_all :
      Repo.t ->
      ?init:(t * commit) list ->
      (t -> commit Irmin.Diff.t -> unit Lwt.t) ->
      watch Lwt.t

    include Irmin.Branch.S with type t := branch
  end

  (** {1 Heads} *)

  module Head : sig
    val list : Repo.t -> commit list Lwt.t
    val find : t -> commit option Lwt.t
    val get : t -> commit Lwt.t
    val set : t -> commit -> unit Lwt.t

    val fast_forward :
      t ->
      ?max_depth:int ->
      ?n:int ->
      commit ->
      ( unit,
        [ `No_change | `Rejected | `Max_depth_reached | `Too_many_lcas ] )
      result
      Lwt.t

    val test_and_set :
      t -> test:commit option -> set:commit option -> bool Lwt.t

    val merge :
      into:t ->
      info:Info.f ->
      ?max_depth:int ->
      ?n:int ->
      commit ->
      (unit, Irmin.Merge.conflict) result Lwt.t
  end

  (** {1 Watches} *)

  val watch :
    t -> ?init:commit -> (commit Irmin.Diff.t -> unit Lwt.t) -> watch Lwt.t

  val watch_key :
    t ->
    path ->
    ?init:commit ->
    ((commit * tree) Irmin.Diff.t -> unit Lwt.t) ->
    watch Lwt.t

  val unwatch : watch -> unit Lwt.t

  (** {1 Type descriptors} *)

  val step_t : step Irmin.Type.t
  val path_t : path Irmin.Type.t
  val metadata_t : metadata Irmin.Type.t
  val contents_t : contents Irmin.Type.t
  val node_t : node Irmin.Type.t
  val tree_t : tree Irmin.Type.t
  val hash_t : hash Irmin.Type.t
  val branch_t : branch Irmin.Type.t
  val slice_t : slice Irmin.Type.t
  val info_t : info Irmin.Type.t
  val lca_error_t : lca_error Irmin.Type.t
  val ff_error_t : ff_error Irmin.Type.t
  val contents_key_t : contents_key Irmin.Type.t
  val node_key_t : node_key Irmin.Type.t
  val commit_key_t : commit_key Irmin.Type.t
  val write_error_t : write_error Irmin.Type.t
  val commit_t : repo -> commit Irmin.Type.t
end

module type S_simple = sig
  type hash

  include
    S
      with type Schema.Hash.t = hash
       and type hash := hash
       and type contents_key = hash
       and type node_key = hash
       and type commit_key = hash
end

module type KV =
  S_simple
    with type Schema.Path.step = string
     and type Schema.Path.t = string list
     and type Schema.Branch.t = string

module type Maker = sig
  type endpoint

  module Make (Schema : Irmin.Schema.S) :
    S
      with module Schema = Schema
       and type Backend.Remote.endpoint = endpoint
       and type contents_key = Schema.Hash.t
       and type node_key = Schema.Hash.t
       and type commit_key = Schema.Hash.t
end

module type KV_maker = sig
  type endpoint
  type metadata
  type info
  type hash

  module Make (C : Irmin.Contents.S) :
    S
      with module Schema.Contents = C
       and type Schema.Metadata.t = metadata
       and type Schema.Hash.t = hash
       and type Schema.Info.t = info
       and type Schema.Path.step = string
       and type Schema.Path.t = string list
       and type Schema.Branch.t = string
       and type Backend.Remote.endpoint = endpoint
       and type contents_key = hash
       and type node_key = hash
       and type commit_key = hash
end

module Make (S : Irmin.Generic_key.S) = struct
  type repo = S.repo
  type t = S.t
  type step = S.step
  type path = S.path
  type metadata = S.metadata
  type contents = S.contents
  type node = S.node
  type tree = S.tree
  type commit = S.commit
  type branch = S.branch
  type slice = S.slice
  type info = S.info
  type hash = S.hash
  type contents_key = S.contents_key
  type node_key = S.node_key
  type commit_key = S.commit_key
  type lca_error = S.lca_error
  type ff_error = S.ff_error
  type write_error = S.write_error
  type kinded_key = [ `Contents of contents_key | `Node of node_key ]

  (* Re-exports of the type-level modules of [S]. These are pure,
     forwarded as-is. *)
  module Schema = S.Schema
  module Info = S.Info
  module Hash = S.Hash
  module Path = S.Path
  module Metadata = S.Metadata
  module History = S.History
  module Status = S.Status

  (* The underlying direct-style Irmin 4 store. Exposed so that downstream
     functors that need a [Generic_key.S] (e.g. [Sync.Make], [Dot]) can be
     applied to the result of [Make]. *)
  module Underlying = S

  (* Lwt-flavoured wrapper of [S.Backend]. The pure / type-level
     submodules ([Schema], [Hash], [Slice], [Node_portable],
     [Commit_portable]) are passed through as-is. The I/O ops of
     [Contents], [Node], [Commit], [Branch] and [Repo] are bridged via
     [run_eio]; callbacks given to [batch] / [watch] / [watch_key] return
     ['_ Lwt.t] and are awaited with [Lwt_eio.Promise.await_lwt] before
     being handed to the underlying direct-style implementation. *)
  module Backend = struct
    module Schema = Schema
    module Hash = S.Backend.Hash

    module Contents = struct
      module Val = S.Backend.Contents.Val
      module Hash = S.Backend.Contents.Hash
      module Key = S.Backend.Contents.Key

      type 'a t = 'a S.Backend.Contents.t
      type key = S.Backend.Contents.key
      type value = S.Backend.Contents.value
      type hash = S.Backend.Contents.hash

      let mem t k = run_eio (fun () -> S.Backend.Contents.mem t k)
      let find t k = run_eio (fun () -> S.Backend.Contents.find t k)
      let close t = run_eio (fun () -> S.Backend.Contents.close t)
      let add t v = run_eio (fun () -> S.Backend.Contents.add t v)

      let unsafe_add t h v =
        run_eio (fun () -> S.Backend.Contents.unsafe_add t h v)

      let index t h = run_eio (fun () -> S.Backend.Contents.index t h)

      let batch t f =
        run_eio (fun () ->
            S.Backend.Contents.batch t (fun rw ->
                Lwt_eio.Promise.await_lwt (f rw)))

      let merge = S.Backend.Contents.merge
    end

    module Node = struct
      module Path = S.Backend.Node.Path
      module Metadata = S.Backend.Node.Metadata
      module Val = S.Backend.Node.Val
      module Hash = S.Backend.Node.Hash
      module Contents = Contents
      module Key = S.Backend.Node.Key

      type 'a t = 'a S.Backend.Node.t
      type key = S.Backend.Node.key
      type value = S.Backend.Node.value
      type hash = S.Backend.Node.hash

      let mem t k = run_eio (fun () -> S.Backend.Node.mem t k)
      let find t k = run_eio (fun () -> S.Backend.Node.find t k)
      let close t = run_eio (fun () -> S.Backend.Node.close t)
      let add t v = run_eio (fun () -> S.Backend.Node.add t v)
      let unsafe_add t h v = run_eio (fun () -> S.Backend.Node.unsafe_add t h v)
      let index t h = run_eio (fun () -> S.Backend.Node.index t h)

      let batch t f =
        run_eio (fun () ->
            S.Backend.Node.batch t (fun rw -> Lwt_eio.Promise.await_lwt (f rw)))

      let merge = S.Backend.Node.merge
    end

    module Node_portable = S.Backend.Node_portable

    module Commit = struct
      module Info = S.Backend.Commit.Info
      module Val = S.Backend.Commit.Val
      module Hash = S.Backend.Commit.Hash
      module Node = Node
      module Key = S.Backend.Commit.Key

      type 'a t = 'a S.Backend.Commit.t
      type key = S.Backend.Commit.key
      type value = S.Backend.Commit.value
      type hash = S.Backend.Commit.hash

      let mem t k = run_eio (fun () -> S.Backend.Commit.mem t k)
      let find t k = run_eio (fun () -> S.Backend.Commit.find t k)
      let close t = run_eio (fun () -> S.Backend.Commit.close t)
      let add t v = run_eio (fun () -> S.Backend.Commit.add t v)

      let unsafe_add t h v =
        run_eio (fun () -> S.Backend.Commit.unsafe_add t h v)

      let index t h = run_eio (fun () -> S.Backend.Commit.index t h)

      let batch t f =
        run_eio (fun () ->
            S.Backend.Commit.batch t (fun rw ->
                Lwt_eio.Promise.await_lwt (f rw)))

      let merge = S.Backend.Commit.merge
    end

    module Commit_portable = S.Backend.Commit_portable

    module Branch = struct
      module Key = S.Backend.Branch.Key
      module Val = S.Backend.Branch.Val

      type t = S.Backend.Branch.t
      type key = S.Backend.Branch.key
      type value = S.Backend.Branch.value
      type watch = S.Backend.Branch.watch

      let mem t k = run_eio (fun () -> S.Backend.Branch.mem t k)
      let find t k = run_eio (fun () -> S.Backend.Branch.find t k)
      let close t = run_eio (fun () -> S.Backend.Branch.close t)
      let list t = run_eio (fun () -> S.Backend.Branch.list t)
      let set t k v = run_eio (fun () -> S.Backend.Branch.set t k v)

      let test_and_set t k ~test ~set =
        run_eio (fun () -> S.Backend.Branch.test_and_set t k ~test ~set)

      let remove t k = run_eio (fun () -> S.Backend.Branch.remove t k)
      let clear t = run_eio (fun () -> S.Backend.Branch.clear t)

      let watch t ?init f =
        run_eio (fun () ->
            S.Backend.Branch.watch t ?init (fun k diff ->
                Lwt_eio.Promise.await_lwt (f k diff)))

      let watch_key t k ?init f =
        run_eio (fun () ->
            S.Backend.Branch.watch_key t k ?init (fun diff ->
                Lwt_eio.Promise.await_lwt (f diff)))

      let unwatch t w = run_eio (fun () -> S.Backend.Branch.unwatch t w)
    end

    module Slice = S.Backend.Slice

    module Repo = struct
      type nonrec t = repo

      let v config = run_eio (fun () -> S.Backend.Repo.v config)
      let close t = run_eio (fun () -> S.Backend.Repo.close t)
      let contents_t = S.Backend.Repo.contents_t
      let node_t = S.Backend.Repo.node_t
      let commit_t = S.Backend.Repo.commit_t
      let config = S.Backend.Repo.config

      let batch ?lock t f =
        run_eio (fun () ->
            S.Backend.Repo.batch ?lock t (fun c n cm ->
                Lwt_eio.Promise.await_lwt (f c n cm)))

      let branch_t = S.Backend.Repo.branch_t
    end

    module Remote = struct
      type t = S.Backend.Remote.t
      type endpoint = S.Backend.Remote.endpoint
      type commit = S.Backend.Remote.commit
      type branch = S.Backend.Remote.branch

      let fetch t ?depth e b =
        run_eio (fun () -> S.Backend.Remote.fetch t ?depth e b)

      let push t ?depth e b =
        run_eio (fun () -> S.Backend.Remote.push t ?depth e b)

      let v r = S.Backend.Remote.v r
    end
  end

  module Contents = struct
    include (S.Contents : Irmin.Contents.S with type t = S.contents)

    let hash = S.Contents.hash
    let of_key r k = run_eio (fun () -> S.Contents.of_key r k)
    let of_hash r h = run_eio (fun () -> S.Contents.of_hash r h)
  end

  module Repo = struct
    type nonrec t = repo
    type elt = S.Repo.elt

    let elt_t = S.Repo.elt_t
    let v config = run_eio (fun () -> S.Repo.v config)
    let close r = run_eio (fun () -> S.Repo.close r)
    let heads r = run_eio (fun () -> S.Repo.heads r)
    let branches r = run_eio (fun () -> S.Repo.branches r)
    let config r = S.Repo.config r

    let export ?full ?depth ?min ?max r =
      run_eio (fun () -> S.Repo.export ?full ?depth ?min ?max r)

    let import t s = run_eio (fun () -> S.Repo.import t s)

    (* Pure: no lazy loading. *)
    let default_pred_commit t k =
      run_eio (fun () -> S.Repo.default_pred_commit t k)

    let default_pred_node t k = run_eio (fun () -> S.Repo.default_pred_node t k)

    let default_pred_contents t k =
      run_eio (fun () -> S.Repo.default_pred_contents t k)

    (* Helpers to bridge the Lwt-returning callbacks of [iter] and
       [breadth_first_traversal] to the direct-style callbacks that the
       underlying Irmin 4 function expects. *)
    let lift_cb1 = function
      | None -> None
      | Some f -> Some (fun x -> Lwt_eio.Promise.await_lwt (f x))

    let lift_cb2 = function
      | None -> None
      | Some f -> Some (fun x y -> Lwt_eio.Promise.await_lwt (f x y))

    let iter ?cache_size ~min ~max ?edge ?branch ?commit ?node ?contents
        ?skip_branch ?skip_commit ?skip_node ?skip_contents ?pred_branch
        ?pred_commit ?pred_node ?pred_contents ?rev t =
      let edge = lift_cb2 edge in
      let branch = lift_cb1 branch in
      let commit = lift_cb1 commit in
      let node = lift_cb1 node in
      let contents = lift_cb1 contents in
      let skip_branch = lift_cb1 skip_branch in
      let skip_commit = lift_cb1 skip_commit in
      let skip_node = lift_cb1 skip_node in
      let skip_contents = lift_cb1 skip_contents in
      let pred_branch = lift_cb2 pred_branch in
      let pred_commit = lift_cb2 pred_commit in
      let pred_node = lift_cb2 pred_node in
      let pred_contents = lift_cb2 pred_contents in
      run_eio (fun () ->
          S.Repo.iter ?cache_size ~min ~max ?edge ?branch ?commit ?node
            ?contents ?skip_branch ?skip_commit ?skip_node ?skip_contents
            ?pred_branch ?pred_commit ?pred_node ?pred_contents ?rev t)

    let breadth_first_traversal ?cache_size ~max ?branch ?commit ?node ?contents
        ?pred_branch ?pred_commit ?pred_node ?pred_contents t =
      let branch = lift_cb1 branch in
      let commit = lift_cb1 commit in
      let node = lift_cb1 node in
      let contents = lift_cb1 contents in
      let pred_branch = lift_cb2 pred_branch in
      let pred_commit = lift_cb2 pred_commit in
      let pred_node = lift_cb2 pred_node in
      let pred_contents = lift_cb2 pred_contents in
      run_eio (fun () ->
          S.Repo.breadth_first_traversal ?cache_size ~max ?branch ?commit ?node
            ?contents ?pred_branch ?pred_commit ?pred_node ?pred_contents t)
  end

  let main r = run_eio (fun () -> S.main r)
  let master r = run_eio (fun () -> S.main r)
  let of_branch r b = run_eio (fun () -> S.of_branch r b)
  let of_commit c = run_eio (fun () -> S.of_commit c)
  let empty r = run_eio (fun () -> S.empty r)

  (* Pure accessors — no I/O, no wrapping needed. *)
  let repo = S.repo
  let status = S.status

  (* [tree] reads from the store handle. Lwt-wrapped to match Irmin 3. *)
  let tree t = run_eio (fun () -> S.tree t)
  let find t p = run_eio (fun () -> S.find t p)
  let find_all t p = run_eio (fun () -> S.find_all t p)
  let mem t p = run_eio (fun () -> S.mem t p)
  let mem_tree t p = run_eio (fun () -> S.mem_tree t p)
  let get t p = run_eio (fun () -> S.get t p)
  let get_all t p = run_eio (fun () -> S.get_all t p)
  let find_tree t p = run_eio (fun () -> S.find_tree t p)
  let get_tree t p = run_eio (fun () -> S.get_tree t p)
  let hash t p = run_eio (fun () -> S.hash t p)
  let kind t p = run_eio (fun () -> S.kind t p)
  let list t p = run_eio (fun () -> S.list t p)
  let key t p = run_eio (fun () -> S.key t p)

  let set ?clear ?retries ?allow_empty ?parents ~info t p v =
    run_eio (fun () -> S.set ?clear ?retries ?allow_empty ?parents ~info t p v)

  let set_exn ?clear ?retries ?allow_empty ?parents ~info t p v =
    run_eio (fun () ->
        S.set_exn ?clear ?retries ?allow_empty ?parents ~info t p v)

  let set_tree ?clear ?retries ?allow_empty ?parents ~info t p tr =
    run_eio (fun () ->
        S.set_tree ?clear ?retries ?allow_empty ?parents ~info t p tr)

  let set_tree_exn ?clear ?retries ?allow_empty ?parents ~info t p tr =
    run_eio (fun () ->
        S.set_tree_exn ?clear ?retries ?allow_empty ?parents ~info t p tr)

  let remove ?clear ?retries ?allow_empty ?parents ~info t p =
    run_eio (fun () -> S.remove ?clear ?retries ?allow_empty ?parents ~info t p)

  let remove_exn ?clear ?retries ?allow_empty ?parents ~info t p =
    run_eio (fun () ->
        S.remove_exn ?clear ?retries ?allow_empty ?parents ~info t p)

  (* Irmin.Type.t descriptors derived by [@@deriving irmin] on [S]. *)
  let step_t = S.step_t
  let path_t = S.path_t
  let metadata_t = S.metadata_t
  let contents_t = S.contents_t
  let node_t = S.node_t
  let tree_t = S.tree_t
  let hash_t = S.hash_t
  let branch_t = S.branch_t
  let slice_t = S.slice_t
  let info_t = S.info_t
  let lca_error_t = S.lca_error_t
  let ff_error_t = S.ff_error_t
  let contents_key_t = S.contents_key_t
  let node_key_t = S.node_key_t
  let commit_key_t = S.commit_key_t
  let write_error_t = S.write_error_t
  let commit_t = S.commit_t

  let test_and_set ?clear ?retries ?allow_empty ?parents ~info t p ~test ~set =
    run_eio (fun () ->
        S.test_and_set ?clear ?retries ?allow_empty ?parents ~info t p ~test
          ~set)

  let test_and_set_exn ?clear ?retries ?allow_empty ?parents ~info t p ~test
      ~set =
    run_eio (fun () ->
        S.test_and_set_exn ?clear ?retries ?allow_empty ?parents ~info t p ~test
          ~set)

  let test_and_set_tree ?clear ?retries ?allow_empty ?parents ~info t p ~test
      ~set =
    run_eio (fun () ->
        S.test_and_set_tree ?clear ?retries ?allow_empty ?parents ~info t p
          ~test ~set)

  let test_and_set_tree_exn ?clear ?retries ?allow_empty ?parents ~info t p
      ~test ~set =
    run_eio (fun () ->
        S.test_and_set_tree_exn ?clear ?retries ?allow_empty ?parents ~info t p
          ~test ~set)

  let test_set_and_get ?clear ?retries ?allow_empty ?parents ~info t p ~test
      ~set =
    run_eio (fun () ->
        S.test_set_and_get ?clear ?retries ?allow_empty ?parents ~info t p ~test
          ~set)

  let test_set_and_get_exn ?clear ?retries ?allow_empty ?parents ~info t p ~test
      ~set =
    run_eio (fun () ->
        S.test_set_and_get_exn ?clear ?retries ?allow_empty ?parents ~info t p
          ~test ~set)

  let test_set_and_get_tree ?clear ?retries ?allow_empty ?parents ~info t p
      ~test ~set =
    run_eio (fun () ->
        S.test_set_and_get_tree ?clear ?retries ?allow_empty ?parents ~info t p
          ~test ~set)

  let test_set_and_get_tree_exn ?clear ?retries ?allow_empty ?parents ~info t p
      ~test ~set =
    run_eio (fun () ->
        S.test_set_and_get_tree_exn ?clear ?retries ?allow_empty ?parents ~info
          t p ~test ~set)

  let merge ?clear ?retries ?allow_empty ?parents ~info ~old t p v =
    run_eio (fun () ->
        S.merge ?clear ?retries ?allow_empty ?parents ~info ~old t p v)

  let merge_exn ?clear ?retries ?allow_empty ?parents ~info ~old t p v =
    run_eio (fun () ->
        S.merge_exn ?clear ?retries ?allow_empty ?parents ~info ~old t p v)

  let merge_tree ?clear ?retries ?allow_empty ?parents ~info ~old t p v =
    run_eio (fun () ->
        S.merge_tree ?clear ?retries ?allow_empty ?parents ~info ~old t p v)

  let merge_tree_exn ?clear ?retries ?allow_empty ?parents ~info ~old t p v =
    run_eio (fun () ->
        S.merge_tree_exn ?clear ?retries ?allow_empty ?parents ~info ~old t p v)

  let with_tree ?clear ?retries ?allow_empty ?parents ?strategy ~info t p f =
    run_eio (fun () ->
        S.with_tree ?clear ?retries ?allow_empty ?parents ?strategy ~info t p f)

  let with_tree_exn ?clear ?retries ?allow_empty ?parents ?strategy ~info t p f
      =
    run_eio (fun () ->
        S.with_tree_exn ?clear ?retries ?allow_empty ?parents ?strategy ~info t
          p f)

  let clone ~src ~dst = run_eio (fun () -> S.clone ~src ~dst)

  type 'a merge =
    info:S.Info.f ->
    ?max_depth:int ->
    ?n:int ->
    'a ->
    (unit, Irmin.Merge.conflict) result Lwt.t

  let merge_into ~into ~info ?max_depth ?n t =
    run_eio (fun () -> S.merge_into ~into ~info ?max_depth ?n t)

  let merge_with_branch t ~info ?max_depth ?n b =
    run_eio (fun () -> S.merge_with_branch t ~info ?max_depth ?n b)

  let merge_with_commit t ~info ?max_depth ?n c =
    run_eio (fun () -> S.merge_with_commit t ~info ?max_depth ?n c)

  let lcas ?max_depth ?n t1 t2 = run_eio (fun () -> S.lcas ?max_depth ?n t1 t2)

  let lcas_with_branch t ?max_depth ?n b =
    run_eio (fun () -> S.lcas_with_branch t ?max_depth ?n b)

  let lcas_with_commit t ?max_depth ?n c =
    run_eio (fun () -> S.lcas_with_commit t ?max_depth ?n c)

  let history ?depth ?min ?max t =
    run_eio (fun () -> S.history ?depth ?min ?max t)

  let last_modified ?depth ?n t p =
    run_eio (fun () -> S.last_modified ?depth ?n t p)

  (* Backend converters. These are pure. *)
  let of_backend_node = S.of_backend_node
  let to_backend_node n = run_eio (fun () -> S.to_backend_node n)

  let to_backend_portable_node n =
    run_eio (fun () -> S.to_backend_portable_node n)

  let to_backend_commit = S.to_backend_commit
  let of_backend_commit = S.of_backend_commit

  (* Extend the top-level [Irmin.remote] the same way [S] does, so the
     identifiers in [Irmin_lwt.Make(S).E] and [S.E] refer to remotes carrying
     the same [endpoint] type. *)
  type Irmin.remote += E of Backend.Remote.endpoint

  (* Saves. These do I/O. *)
  let save_contents c v = run_eio (fun () -> S.save_contents c v)
  let save_tree ?clear r c n t = run_eio (fun () -> S.save_tree ?clear r c n t)

  module Tree = struct
    type nonrec t = tree

    (* Polymorphic variants: declared transparently here. They are
       structurally identical to the upstream [S.Tree.X] versions, so
       values flow through without coercion thanks to polymorphic-variant
       subtyping. *)
    type kinded_hash = [ `Contents of hash * metadata | `Node of hash ]

    type kinded_key =
      [ `Contents of contents_key * metadata | `Node of node_key ]

    type elt = [ `Node of node | `Contents of contents * metadata ]

    type concrete =
      [ `Tree of (step * concrete) list | `Contents of contents * metadata ]

    (* [stats] is a record. We keep it as an alias of [S.Tree.stats] so
       it remains nominally compatible. Field access is exposed through
       [stats_t] / [Irmin.Type] introspection. *)
    type stats = S.Tree.stats

    let kinded_key_t = S.Tree.kinded_key_t
    let stats_t = S.Tree.stats_t

    type error = S.Tree.error
    type 'a or_error = ('a, error) result

    exception Dangling_hash = S.Tree.Dangling_hash
    exception Pruned_hash = S.Tree.Pruned_hash
    exception Portable_value = S.Tree.Portable_value

    module Contents = struct
      include (
        S.Tree.Contents :
          module type of struct
            include S.Tree.Contents
          end
          with type t = S.Tree.Contents.t)

      let force c = run_eio (fun () -> S.Tree.Contents.force c)
      let force_exn c = run_eio (fun () -> S.Tree.Contents.force_exn c)
    end

    (* Pure constructors and inspectors. *)
    let empty = S.Tree.empty
    let singleton = S.Tree.singleton
    let of_contents = S.Tree.of_contents
    let of_node = S.Tree.of_node
    let v = S.Tree.v
    let pruned = S.Tree.pruned
    let is_empty = S.Tree.is_empty
    let destruct = S.Tree.destruct
    let hash = S.Tree.hash
    let kinded_hash = S.Tree.kinded_hash
    let key = S.Tree.key
    let shallow = S.Tree.shallow
    let clear = S.Tree.clear
    let of_concrete = S.Tree.of_concrete
    let pp = S.Tree.pp

    (* I/O-performing ops, wrapped. *)
    let kind t p = run_eio (fun () -> S.Tree.kind t p)
    let diff x y = run_eio (fun () -> S.Tree.diff x y)
    let mem t p = run_eio (fun () -> S.Tree.mem t p)
    let find_all t p = run_eio (fun () -> S.Tree.find_all t p)
    let length t ?cache p = run_eio (fun () -> S.Tree.length t ?cache p)
    let find t p = run_eio (fun () -> S.Tree.find t p)
    let get_all t p = run_eio (fun () -> S.Tree.get_all t p)
    let get t p = run_eio (fun () -> S.Tree.get t p)

    let list t ?offset ?length ?cache p =
      run_eio (fun () -> S.Tree.list t ?offset ?length ?cache p)

    let seq t ?offset ?length ?cache p =
      run_eio (fun () -> S.Tree.seq t ?offset ?length ?cache p)

    let add t p ?metadata c = run_eio (fun () -> S.Tree.add t p ?metadata c)

    let update t p ?metadata f =
      run_eio (fun () -> S.Tree.update t p ?metadata f)

    let remove t p = run_eio (fun () -> S.Tree.remove t p)
    let mem_tree t p = run_eio (fun () -> S.Tree.mem_tree t p)
    let find_tree t p = run_eio (fun () -> S.Tree.find_tree t p)
    let get_tree t p = run_eio (fun () -> S.Tree.get_tree t p)
    let add_tree t p sub = run_eio (fun () -> S.Tree.add_tree t p sub)
    let update_tree t p f = run_eio (fun () -> S.Tree.update_tree t p f)
    let stats ?force t = run_eio (fun () -> S.Tree.stats ?force t)
    let to_concrete t = run_eio (fun () -> S.Tree.to_concrete t)
    let find_key r t = run_eio (fun () -> S.Tree.find_key r t)
    let of_key r k = run_eio (fun () -> S.Tree.of_key r k)
    let of_hash r h = run_eio (fun () -> S.Tree.of_hash r h)

    (* [fold] accepts Lwt-returning folders as Irmin 3 did; each folder is
       bridged to direct style via [Lwt_eio.Promise.await_lwt] before being
       handed to the underlying Irmin 4 [S.Tree.fold]. *)
    type marks = S.Tree.marks

    let empty_marks = S.Tree.empty_marks

    type 'a force = [ `True | `False of path -> 'a -> 'a Lwt.t ]
    type uniq = [ `False | `True | `Marks of marks ]
    type ('a, 'b) folder = path -> 'b -> 'a -> 'a Lwt.t
    type depth = S.Tree.depth

    let lift_folder = function
      | None -> None
      | Some (f : _ folder) ->
          Some (fun path b acc -> Lwt_eio.Promise.await_lwt (f path b acc))

    let lift_force = function
      | None -> None
      | Some `True -> Some `True
      | Some (`False f) ->
          Some (`False (fun path acc -> Lwt_eio.Promise.await_lwt (f path acc)))

    let fold ?order ?force ?cache ?uniq ?pre ?post ?depth ?contents ?node ?tree
        t acc =
      let force = lift_force force in
      let pre = lift_folder pre in
      let post = lift_folder post in
      let contents = lift_folder contents in
      let node = lift_folder node in
      let tree = lift_folder tree in
      run_eio (fun () ->
          S.Tree.fold ?order ?force ?cache ?uniq ?pre ?post ?depth ?contents
            ?node ?tree t acc)

    let merge = S.Tree.merge

    type counters = S.Tree.counters

    let counters = S.Tree.counters
    let dump_counters = S.Tree.dump_counters
    let reset_counters = S.Tree.reset_counters
    let inspect = S.Tree.inspect

    module Proof = struct
      include (
        S.Tree.Proof :
          module type of struct
            include S.Tree.Proof
          end
          with type tree := S.Tree.Proof.tree
           and type t := S.Tree.Proof.t)

      type tree = S.Tree.Proof.tree =
        | Contents of S.contents * S.metadata
        | Blinded_contents of S.hash * S.metadata
        | Node of (S.step * tree) list
        | Blinded_node of S.hash
        | Inode of inode_tree inode
        | Extender of inode_tree inode_extender

      and inode_tree = S.Tree.Proof.inode_tree =
        | Blinded_inode of S.hash
        | Inode_values of (S.step * tree) list
        | Inode_tree of inode_tree inode
        | Inode_extender of inode_tree inode_extender

      type t = S.Tree.Proof.t

      let v = S.Tree.Proof.v
      let before = S.Tree.Proof.before
      let after = S.Tree.Proof.after
      let state = S.Tree.Proof.state
      let to_tree = S.Tree.Proof.to_tree
    end

    type verifier_error = [ `Proof_mismatch of string ]

    let produce_proof repo key f =
      let f' tree = Lwt_eio.Promise.await_lwt (f tree) in
      run_eio (fun () -> S.Tree.produce_proof repo key f')

    let verify_proof proof f =
      let f' tree = Lwt_eio.Promise.await_lwt (f tree) in
      run_eio (fun () -> S.Tree.verify_proof proof f')

    let hash_of_proof_state = S.Tree.hash_of_proof_state
  end

  module Commit = struct
    type nonrec t = commit
    type commit_key = S.commit_key

    (* Pure accessors. *)
    let tree = S.Commit.tree
    let parents = S.Commit.parents
    let info = S.Commit.info
    let hash = S.Commit.hash
    let key = S.Commit.key
    let pp = S.Commit.pp
    let pp_hash = S.Commit.pp_hash

    (* I/O-performing. *)
    let v ?clear r ~info ~parents tree =
      run_eio (fun () -> S.Commit.v ?clear r ~info ~parents tree)

    let of_key r k = run_eio (fun () -> S.Commit.of_key r k)
    let of_hash r h = run_eio (fun () -> S.Commit.of_hash r h)
  end

  module Branch = struct
    type nonrec t = branch

    let mem r b = run_eio (fun () -> S.Branch.mem r b)
    let find r b = run_eio (fun () -> S.Branch.find r b)
    let get r b = run_eio (fun () -> S.Branch.get r b)
    let set r b c = run_eio (fun () -> S.Branch.set r b c)
    let remove r b = run_eio (fun () -> S.Branch.remove r b)
    let list r = run_eio (fun () -> S.Branch.list r)
    let pp = S.Branch.pp

    let watch r b ?init lwt_cb =
      let cb diff = Lwt_eio.Promise.await_lwt (lwt_cb diff) in
      run_eio (fun () -> S.Branch.watch r b ?init cb)

    let watch_all r ?init lwt_cb =
      let cb br diff = Lwt_eio.Promise.await_lwt (lwt_cb br diff) in
      run_eio (fun () -> S.Branch.watch_all r ?init cb)

    let main = S.Branch.main
    let is_valid = S.Branch.is_valid
    let t = S.Branch.t
  end

  module Head = struct
    let list r = run_eio (fun () -> S.Head.list r)
    let find t = run_eio (fun () -> S.Head.find t)
    let get t = run_eio (fun () -> S.Head.get t)
    let set t c = run_eio (fun () -> S.Head.set t c)

    let fast_forward t ?max_depth ?n c =
      run_eio (fun () -> S.Head.fast_forward t ?max_depth ?n c)

    let test_and_set t ~test ~set =
      run_eio (fun () -> S.Head.test_and_set t ~test ~set)

    let merge ~into ~info ?max_depth ?n c =
      run_eio (fun () -> S.Head.merge ~into ~info ?max_depth ?n c)
  end

  type watch = S.watch
  (** Top-level watches. *)

  let watch t ?init lwt_cb =
    let cb diff = Lwt_eio.Promise.await_lwt (lwt_cb diff) in
    run_eio (fun () -> S.watch t ?init cb)

  let watch_key t path ?init lwt_cb =
    let cb diff = Lwt_eio.Promise.await_lwt (lwt_cb diff) in
    run_eio (fun () -> S.watch_key t path ?init cb)

  let unwatch w = run_eio (fun () -> S.unwatch w)
end

(* Lwt wrappers for [irmin-pack-unix]-specific operations.

   [Pack.Make] takes an [Irmin_pack_io.S] (the full pack-unix store
   signature) and returns a module that:
   - [include]s [Make (S)] — every generic-key Lwt-wrapped operation is
     available;
   - additionally exposes Lwt-wrapped versions of the pack-unix
     extensions: integrity check, GC, snapshots, split/reload/flush,
     [create_one_commit_store]. *)
module Pack = struct
  module Make (S : Irmin_pack_io.S) = struct
    include Make (S)

    let integrity_check ?ppf ?heads ~auto_repair r =
      run_eio (fun () -> S.integrity_check ?ppf ?heads ~auto_repair r)

    let integrity_check_inodes ?heads r =
      run_eio (fun () -> S.integrity_check_inodes ?heads r)

    let traverse_pack_file kind conf =
      run_eio (fun () -> S.traverse_pack_file kind conf)

    let test_traverse_pack_file kind conf =
      run_eio (fun () -> S.test_traverse_pack_file kind conf)

    let split r = run_eio (fun () -> S.split r)
    let is_split_allowed r = S.is_split_allowed r
    let add_volume r = run_eio (fun () -> S.add_volume r)
    let reload r = run_eio (fun () -> S.reload r)
    let flush r = run_eio (fun () -> S.flush r)

    let create_one_commit_store ~domain_mgr r ck path =
      run_eio (fun () -> S.create_one_commit_store ~domain_mgr r ck path)

    module Gc = struct
      type process_state = S.Gc.process_state
      type msg = S.Gc.msg

      let start_exn ~domain_mgr ?unlink r c =
        run_eio (fun () -> S.Gc.start_exn ~domain_mgr ?unlink r c)

      let finalise_exn ?wait r = run_eio (fun () -> S.Gc.finalise_exn ?wait r)

      let run ~domain_mgr ?finished r c =
        let finished =
          Option.map
            (fun lwt_f result -> Lwt_eio.Promise.await_lwt (lwt_f result))
            finished
        in
        run_eio (fun () -> S.Gc.run ~domain_mgr ?finished r c)

      let wait r = run_eio (fun () -> S.Gc.wait r)
      let cancel r = run_eio (fun () -> S.Gc.cancel r)
      let is_finished r = S.Gc.is_finished r
      let behaviour r = S.Gc.behaviour r
      let is_allowed r = S.Gc.is_allowed r
      let latest_gc_target r = S.Gc.latest_gc_target r
    end

    module Snapshot = struct
      include S.Snapshot

      let export ?on_disk r f ~root_key =
        run_eio (fun () -> S.Snapshot.export ?on_disk r f ~root_key)
    end
  end
end

(* Alias for the top-level [module type S] of [Irmin_lwt], so that
   [Sync.Make] can refer to it without colliding with [Sync]'s own
   [module type S]. *)
module type Lwt_store = S

module Node = struct
  module Graph (X : Lwt_store) = struct
    module G = Irmin.Node.Graph (X.Underlying.Backend.Node)

    type 'a t = 'a X.Underlying.Backend.Node.t
    type metadata = X.metadata
    type contents_key = X.contents_key
    type node_key = X.node_key
    type step = X.step
    type path = X.path
    type value = [ `Node of node_key | `Contents of contents_key * metadata ]

    let value_t = G.value_t
    let empty t = run_eio (fun () -> G.empty t)
    let v t kvs = run_eio (fun () -> G.v t kvs)
    let list t k = run_eio (fun () -> G.list t k)
    let find t k p = run_eio (fun () -> G.find t k p)
    let add t k p v = run_eio (fun () -> G.add t k p v)
    let remove t k p = run_eio (fun () -> G.remove t k p)
    let closure t ~min ~max = run_eio (fun () -> G.closure t ~min ~max)

    let iter t ~min ~max ?node ?contents ?edge ?skip_node ?skip_contents ?rev ()
        =
      let lift1 f = Option.map (fun g x -> Lwt_eio.Promise.await_lwt (g x)) f in
      let lift2 f =
        Option.map (fun g x y -> Lwt_eio.Promise.await_lwt (g x y)) f
      in
      run_eio (fun () ->
          G.iter t ~min ~max ?node:(lift1 node) ?contents:(lift1 contents)
            ?edge:(lift2 edge) ?skip_node:(lift1 skip_node)
            ?skip_contents:(lift1 skip_contents) ?rev ())
  end
end

module Commit = struct
  module History (X : Lwt_store) = struct
    module H = Irmin.Commit.History (X.Underlying.Backend.Commit)

    type 'a t = 'a X.Underlying.Backend.Commit.t
    type node_key = X.node_key
    type commit_key = X.commit_key
    type v = X.Underlying.Backend.Commit.value
    type info = X.info

    let v t ~node ~parents ~info =
      run_eio (fun () -> H.v t ~node ~parents ~info)

    let parents t k = run_eio (fun () -> H.parents t k)
    let merge t ~info = H.merge t ~info

    let lcas t ?max_depth ?n c1 c2 =
      run_eio (fun () -> H.lcas t ?max_depth ?n c1 c2)

    let lca t ~info ?max_depth ?n cs =
      run_eio (fun () -> H.lca t ~info ?max_depth ?n cs)

    let three_way_merge t ~info ?max_depth ?n c1 c2 =
      run_eio (fun () -> H.three_way_merge t ~info ?max_depth ?n c1 c2)

    let closure t ~min ~max = run_eio (fun () -> H.closure t ~min ~max)

    let iter t ~min ~max ?commit ?edge ?skip ?rev () =
      let lift1 f = Option.map (fun g x -> Lwt_eio.Promise.await_lwt (g x)) f in
      let lift2 f =
        Option.map (fun g x y -> Lwt_eio.Promise.await_lwt (g x y)) f
      in
      let commit = lift1 commit in
      let edge = lift2 edge in
      let skip = lift1 skip in
      run_eio (fun () -> H.iter t ~min ~max ?commit ?edge ?skip ?rev ())
  end
end

module Sync = struct
  module type S = sig
    type db
    type commit
    type status = [ `Empty | `Head of commit ]
    type info

    val status_t : db -> status Irmin.Type.t
    val pp_status : status Fmt.t

    val fetch :
      db ->
      ?depth:int ->
      Irmin.remote ->
      (status, [ `Msg of string ]) result Lwt.t

    val fetch_exn : db -> ?depth:int -> Irmin.remote -> status Lwt.t

    type pull_error = [ `Msg of string | Irmin.Merge.conflict ]

    val pp_pull_error : pull_error Fmt.t

    val pull :
      db ->
      ?depth:int ->
      Irmin.remote ->
      [ `Merge of unit -> info | `Set ] ->
      (status, pull_error) result Lwt.t

    val pull_exn :
      db ->
      ?depth:int ->
      Irmin.remote ->
      [ `Merge of unit -> info | `Set ] ->
      status Lwt.t

    type push_error = [ `Msg of string | `Detached_head ]

    val pp_push_error : push_error Fmt.t

    val push :
      db -> ?depth:int -> Irmin.remote -> (status, push_error) result Lwt.t

    val push_exn : db -> ?depth:int -> Irmin.remote -> status Lwt.t
  end

  module Make (X : Lwt_store) = struct
    module S = Irmin.Sync.Make (X.Underlying)

    type db = X.t
    type commit = X.commit
    type status = [ `Empty | `Head of commit ]
    type info = X.info

    let status_t = S.status_t
    let pp_status = S.pp_status
    let fetch db ?depth r = run_eio (fun () -> S.fetch db ?depth r)
    let fetch_exn db ?depth r = run_eio (fun () -> S.fetch_exn db ?depth r)

    type pull_error = S.pull_error

    let pp_pull_error = S.pp_pull_error
    let pull db ?depth r s = run_eio (fun () -> S.pull db ?depth r s)
    let pull_exn db ?depth r s = run_eio (fun () -> S.pull_exn db ?depth r s)

    type push_error = S.push_error

    let pp_push_error = S.pp_push_error
    let push db ?depth r = run_eio (fun () -> S.push db ?depth r)
    let push_exn db ?depth r = run_eio (fun () -> S.push_exn db ?depth r)
  end
end

let remote_store = Irmin.remote_store

module Json_tree
    (Store : Irmin.S with type Schema.Contents.t = Irmin.Contents.json) =
struct
  module J = Irmin.Json_tree (Store)
  include (J : Irmin.Contents.S with type t = Irmin.Contents.json)

  let to_concrete_tree = J.to_concrete_tree
  let of_concrete_tree = J.of_concrete_tree
  let get_tree tree path = run_eio (fun () -> J.get_tree tree path)
  let set_tree tree path v = run_eio (fun () -> J.set_tree tree path v)
  let get t path = run_eio (fun () -> J.get t path)
  let set t path v ~info = run_eio (fun () -> J.set t path v ~info)
end

module Dot (S : Lwt_store) = struct
  module D = Irmin.Dot (S.Underlying)

  type db = S.t

  let output_buffer db ?html ?depth ?full ~date buf =
    run_eio (fun () -> D.output_buffer db ?html ?depth ?full ~date buf)
end
