open! Core_kernel
open! Import
module Bonsai_lib = Bonsai
open Proc
open Bonsai.Let_syntax
module Query_response_tracker = Bonsai.Effect.For_testing.Query_response_tracker

let%expect_test "cutoff" =
  let var = Bonsai.Var.create 0 in
  let value = Bonsai.Var.value var in
  let component = return @@ Bonsai.Value.cutoff value ~equal:(fun a b -> a % 2 = b % 2) in
  let handle = Handle.create (Result_spec.string (module Int)) component in
  Handle.show handle;
  [%expect {| 0 |}];
  Bonsai.Var.set var 2;
  Handle.show handle;
  [%expect {| 0 |}];
  Bonsai.Var.set var 1;
  Handle.show handle;
  [%expect {| 1 |}]
;;

let%expect_test "mapn" =
  let (_ : unit Bonsai.Computation.t) =
    let%mapn.Bonsai.Computation () = Bonsai.const ()
    and () = Bonsai.const ()
    and () = Bonsai.const () in
    ()
  in
  ()
;;

let%expect_test "if_" =
  let component input =
    let a = Bonsai.Value.return "hello" in
    let b = Bonsai.Value.return "world" in
    (Bonsai.if_
       input
       ~then_:(Bonsai.read a)
       ~else_:(Bonsai.read b) [@alert "-deprecated"])
  in
  let var = Bonsai.Var.create true in
  let handle =
    Handle.create (Result_spec.string (module String)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {| hello |}];
  Bonsai.Var.set var false;
  Handle.show handle;
  [%expect {| world |}]
;;

let%expect_test "call component" =
  let add_one = Bonsai.pure (fun x -> x + 1) in
  let component input =
    let%sub a = add_one input in
    return a
  in
  let var = Bonsai.Var.create 1 in
  let handle =
    Handle.create (Result_spec.sexp (module Int)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {| 2 |}];
  Bonsai.Var.set var 2;
  Handle.show handle;
  [%expect {| 3 |}]
;;

let%expect_test "on_display" =
  let component =
    let%sub state, set_state = Bonsai.state [%here] (module Int) ~default_model:0 in
    let update =
      let%map state = state
      and set_state = set_state in
      set_state (state + 1)
    in
    let%sub () = Bonsai.Edge.after_display update in
    return state
  in
  let handle = Handle.create (Result_spec.sexp (module Int)) component in
  Handle.show handle;
  [%expect {| 0 |}];
  Handle.show handle;
  [%expect {| 1 |}];
  Handle.show handle;
  [%expect {| 2 |}];
  Handle.show handle;
  [%expect {| 3 |}]
;;

let%expect_test "on_display for updating a state" =
  let component input =
    let%sub state, set_state = Bonsai.state_opt [%here] (module Int) in
    let%sub update =
      match%sub state with
      | None ->
        return
        @@ let%map set_state = set_state
        and input = input in
        Some (set_state (Some input))
      | Some state ->
        return
        @@ let%map state = state
        and set_state = set_state
        and input = input in
        if Int.equal state input then None else Some (set_state (Some input))
    in
    let%sub () = Bonsai.Edge.after_display' update in
    return (Bonsai.Value.both input state)
  in
  let var = Bonsai.Var.create 1 in
  let handle =
    Handle.create
      (Result_spec.sexp
         (module struct
           type t = int * int option [@@deriving sexp_of]
         end))
      (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {| (1 ()) |}];
  Handle.show handle;
  [%expect {| (1 (1)) |}];
  Handle.show handle;
  [%expect {| (1 (1)) |}];
  Bonsai.Var.set var 2;
  Handle.show handle;
  [%expect {| (2 (1)) |}];
  Handle.show handle;
  [%expect {| (2 (2)) |}];
  Handle.show handle;
  [%expect {| (2 (2)) |}]
;;

let%expect_test "path" =
  let component =
    let%sub () = Bonsai.const () in
    let%sub path = Bonsai.Private.path in
    return (Bonsai.Value.map path ~f:Bonsai.Private.Path.sexp_of_t)
  in
  let handle = Handle.create (Result_spec.sexp (module Sexp)) component in
  Handle.show handle;
  (* The first of these "Subst_from" is actually a component that is
     added by the testing helpers. *)
  [%expect {| (Subst_from Subst_into Subst_from) |}]
;;

let%expect_test "assoc and enum path" =
  let component =
    Bonsai.assoc
      (module Int)
      (Bonsai.Value.return (Int.Map.of_alist_exn [ -1, (); 1, () ]))
      ~f:(fun i _ ->
        if%sub i >>| ( > ) 0 then Bonsai.Private.path else Bonsai.Private.path)
  in
  let handle =
    Handle.create
      (Result_spec.sexp
         (module struct
           type t = Bonsai.Private.Path.t Int.Map.t [@@deriving sexp_of]
         end))
      component
  in
  Handle.show handle;
  [%expect
    {|
    ((-1 (Subst_from (Assoc -1) Subst_into (Enum 0)))
     (1 (Subst_from (Assoc 1) Subst_into (Enum 1)))) |}]
;;

let%expect_test "chain" =
  let add_one = Bonsai.pure (fun x -> x + 1) in
  let double = Bonsai.pure (fun x -> x * 2) in
  let component input =
    let%sub a = add_one input in
    let%sub b = double a in
    return b
  in
  let var = Bonsai.Var.create 1 in
  let handle =
    Handle.create (Result_spec.sexp (module Int)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {| 4 |}];
  Bonsai.Var.set var 2;
  Handle.show handle;
  [%expect {| 6 |}]
;;

let%expect_test "chain + both" =
  let add_one = Bonsai.pure (fun x -> x + 1) in
  let double = Bonsai.pure (fun x -> x * 2) in
  let add = Bonsai.pure (fun (x, y) -> x + y) in
  let component input =
    let%sub a = add_one input in
    let%sub b = double a in
    let%sub c = add (Bonsai.Value.both a b) in
    return c
  in
  let var = Bonsai.Var.create 1 in
  let handle =
    Handle.create (Result_spec.sexp (module Int)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {| 6 |}];
  Bonsai.Var.set var 2;
  Handle.show handle;
  [%expect {| 9 |}]
;;

let%expect_test "wrap" =
  let component =
    Bonsai.wrap
      (module Int)
      ~default_model:0
      ~apply_action:(fun ~inject:_ ~schedule_event:_ (result, _) model () ->
        String.length result + model)
      ~f:(fun model inject ->
        return
        @@ let%map model = model
        and inject = inject in
        Int.to_string model, inject)
  in
  let handle =
    Handle.create
      (module struct
        type t = string * (unit -> Event.t)
        type incoming = unit

        let view = Tuple2.get1
        let incoming (_, x) () = x ()
      end)
      component
  in
  Handle.show handle;
  [%expect {| 0 |}];
  Handle.do_actions handle [ () ];
  Handle.show handle;
  [%expect {| 1 |}];
  Handle.do_actions handle [ (); (); (); (); (); (); (); (); (); () ];
  Handle.show handle;
  [%expect {| 12 |}];
  Handle.do_actions handle [ () ];
  Handle.show handle;
  [%expect {| 14 |}]
;;

let%expect_test "match_either" =
  let var : (string, int) Either.t Bonsai.Var.t =
    Bonsai.Var.create (Either.First "hello")
  in
  let component =
    (Bonsai.match_either
       (Bonsai.Var.value var)
       ~first:(fun s -> Bonsai.read (Bonsai.Value.map s ~f:(sprintf "%s world")))
       ~second:(fun i -> Bonsai.read (Bonsai.Value.map i ~f:Int.to_string))
     [@alert "-deprecated"])
  in
  let handle = Handle.create (Result_spec.string (module String)) component in
  Handle.show handle;
  [%expect {| hello world |}];
  Bonsai.Var.set var (Second 2);
  Handle.show handle;
  [%expect {| 2 |}]
;;

let%expect_test "match%sub" =
  let var : (string, int) Either.t Bonsai.Var.t =
    Bonsai.Var.create (Either.First "hello")
  in
  let component =
    match%sub Bonsai.Var.value var with
    | First s -> Bonsai.read (Bonsai.Value.map s ~f:(sprintf "%s world"))
    | Second i -> Bonsai.read (Bonsai.Value.map i ~f:Int.to_string)
  in
  let handle = Handle.create (Result_spec.string (module String)) component in
  Handle.show handle;
  [%expect {| hello world |}];
  Bonsai.Var.set var (Second 2);
  Handle.show handle;
  [%expect {| 2 |}]
;;

type thing =
  | Loading of string
  | Search_results of int

let%expect_test "match%sub repro" =
  let open Bonsai.Let_syntax in
  let component current_page =
    match%sub current_page with
    | Loading x ->
      Bonsai.read
        (let%map x = x in
         "loading " ^ x)
    | Search_results s ->
      Bonsai.read
        (let%map s = s in
         sprintf "search results %d" s)
  in
  let var = Bonsai.Var.create (Loading "hello") in
  let handle =
    Handle.create (Result_spec.string (module String)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {| loading hello |}];
  Bonsai.Var.set var (Search_results 5);
  Handle.show handle;
  [%expect {| search results 5 |}]
;;

let%expect_test "if%sub" =
  let component input =
    let a = Bonsai.Value.return "hello" in
    let b = Bonsai.Value.return "world" in
    if%sub input then Bonsai.read a else Bonsai.read b
  in
  let var = Bonsai.Var.create true in
  let handle =
    Handle.create (Result_spec.string (module String)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {| hello |}];
  Bonsai.Var.set var false;
  Handle.show handle;
  [%expect {| world |}]
;;

let%expect_test "let%sub patterns" =
  let component =
    let%sub a, _b = Bonsai.const ("hello world", 5) in
    return a
  in
  let handle = Handle.create (Result_spec.string (module String)) component in
  Handle.show handle;
  [%expect {| hello world |}]
;;

let%expect_test "assoc simplifies its inner computation, if possible" =
  let value = Bonsai.Value.return String.Map.empty in
  let component =
    Bonsai.assoc
      (module String)
      value
      ~f:(fun key data -> Bonsai.read (Bonsai.Value.both key data))
  in
  print_s Bonsai_lib.Private.(Computation.sexp_of_packed (reveal_computation component));
  [%expect {| (Assoc_simpl ((map constant))) |}]
;;

let%expect_test "action sent to non-existent assoc element" =
  let var = Bonsai.Var.create (Int.Map.of_alist_exn [ 1, (); 2, () ]) in
  let component =
    Bonsai.assoc
      (module Int)
      (Bonsai.Var.value var)
      ~f:(fun _key _data -> Bonsai.state [%here] (module Int) ~default_model:0)
  in
  let handle =
    Handle.create
      (module struct
        type t = (int * (int -> Event.t)) Int.Map.t
        type incoming = Nothing.t

        let incoming _ = Nothing.unreachable_code

        let view (map : t) =
          map
          |> Map.to_alist
          |> List.map ~f:(fun (i, (s, _)) -> i, s)
          |> [%sexp_of: (int * int) list]
          |> Sexp.to_string_hum
        ;;
      end)
      component
  in
  Handle.show handle;
  [%expect {|
        ((1 0) (2 0)) |}];
  let result = Handle.result handle in
  let set_two what =
    result
    |> Fn.flip Map.find_exn 2
    |> Tuple2.get2
    |> Fn.flip ( @@ ) what
    |> Ui_event.Expert.handle
  in
  set_two 3;
  Handle.show handle;
  [%expect {| ((1 0) (2 3)) |}];
  Bonsai.Var.set var (Int.Map.of_alist_exn [ 1, () ]);
  Handle.show handle;
  [%expect {| ((1 0)) |}];
  set_two 4;
  Handle.show handle;
  [%expect
    {|
    ("an action inside of Bonsai.assoc as been dropped because the computation is no longer active"
     (key 2) (action 4))
    ((1 0)) |}]
;;

let%test_module "testing Bonsai internals" =
  (module struct
    (* This module tests internal details of Bonsai, and the results are sensitive to
       implementation changes. *)
    [@@@alert "-rampantly_nondeterministic"]

    let%expect_test "remove unused models in assoc" =
      let var = Bonsai.Var.create Int.Map.empty in
      let module State_with_setter = struct
        type t =
          { state : string
          ; set_state : string -> Event.t
          }
      end
      in
      let module Action = struct
        type t = Set of string
      end
      in
      let component =
        Bonsai.assoc
          (module Int)
          (Bonsai.Var.value var)
          ~f:(fun _key _data ->
            let%sub v = Bonsai.state [%here] (module String) ~default_model:"hello" in
            return
            @@ let%map state, set_state = v in
            { State_with_setter.state; set_state })
      in
      let handle =
        Handle.create
          (module struct
            type t = State_with_setter.t Int.Map.t
            type incoming = int * Action.t

            let incoming (map : t) (id, action) =
              let t = Map.find_exn map id in
              match (action : Action.t) with
              | Set value -> t.set_state value
            ;;

            let view (map : t) =
              map
              |> Map.to_alist
              |> List.map ~f:(fun (i, { state; set_state = _ }) -> i, state)
              |> [%sexp_of: (int * string) list]
              |> Sexp.to_string_hum
            ;;
          end)
          component
      in
      Handle.show_model handle;
      [%expect {|
        (()
         ()) |}];
      Bonsai.Var.set var (Int.Map.of_alist_exn [ 1, (); 2, () ]);
      Handle.show_model handle;
      [%expect {|
        (()
         ()) |}];
      (* use the setter to re-establish the default *)
      Handle.do_actions handle [ 1, Set "test" ];
      Handle.show_model handle;
      [%expect {| (((1 (test ()))) ()) |}];
      Handle.do_actions handle [ 1, Set "hello" ];
      Handle.show_model handle;
      [%expect {|
        (()
         ()) |}]
    ;;
  end)
;;

let%expect_test "multiple maps respect cutoff" =
  let component input =
    input
    |> Bonsai.Value.map ~f:(fun (_ : int) -> ())
    |> Bonsai.Value.map ~f:(fun () -> print_endline "triggered")
    |> return
  in
  let var = Bonsai.Var.create 1 in
  let handle =
    Handle.create (Result_spec.sexp (module Unit)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {|
    triggered
    () |}];
  Bonsai.Var.set var 2;
  (* Cutoff happens on the unit, so "triggered" isn't printed *)
  Handle.show handle;
  [%expect {| () |}]
;;

let%expect_test "let syntax is collapsed upon eval" =
  let value =
    let%map () = Bonsai.Value.return ()
    and () = Bonsai.Value.return ()
    and () = Bonsai.Value.return ()
    and () = Bonsai.Value.return ()
    and () = Bonsai.Value.return ()
    and () = Bonsai.Value.return ()
    and () = Bonsai.Value.return () in
    ()
  in
  let packed =
    let open Bonsai.Private in
    value |> reveal_value |> Value.eval Environment.empty |> Incr.pack
  in
  let filename = Stdlib.Filename.temp_file "incr" "out" in
  Incremental.Packed.save_dot filename [ packed ];
  let dot_contents = In_channel.read_all filename in
  require
    [%here]
    ~if_false_then_print_s:(lazy [%message "No Map7 node found"])
    (String.is_substring dot_contents ~substring:"Map7");
  [%expect {| |}]
;;

let%test_unit "constant prop doesn't happen" =
  (* Just make sure that this expression doesn't crash *)
  let (_ : int Bonsai.Computation.t) =
    (Bonsai.match_either
       (Bonsai.Value.return (First 1))
       ~first:Bonsai.read
       ~second:Bonsai.read [@alert "-deprecated"])
  in
  ()
;;

let%expect_test "ignored result of assoc" =
  let var = Bonsai.Var.create (Int.Map.of_alist_exn [ 1, (); 2, () ]) in
  let component =
    let%sub _ =
      Bonsai.assoc
        (module Int)
        (Bonsai.Var.value var)
        ~f:(fun _key data ->
          (* this sub is here to make sure that bonsai doesn't
             optimize the component into an "assoc_simple" *)
          let%sub _ = Bonsai.const () in
          Bonsai.read data)
    in
    Bonsai.const ()
  in
  let handle = Handle.create (Result_spec.sexp (module Unit)) component in
  Handle.show handle;
  [%expect {| () |}];
  Bonsai.Var.set var (Int.Map.of_alist_exn []);
  Expect_test_helpers_core.require_does_not_raise [%here] (fun () -> Handle.show handle);
  [%expect {| () |}]
;;

let%expect_test "on_display for updating a state (using on_change)" =
  let callback =
    Bonsai.Value.return (fun prev cur ->
      Ui_event.print_s [%message "change!" (prev : int option) (cur : int)])
  in
  let component input = Bonsai.Edge.on_change' [%here] (module Int) ~callback input in
  let var = Bonsai.Var.create 1 in
  let handle =
    Handle.create
      (Result_spec.sexp
         (module struct
           type t = unit

           let sexp_of_t () = Sexp.Atom "rendering..."
         end))
      (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {|
    rendering...
    (change! (prev ()) (cur 1)) |}];
  Handle.show handle;
  [%expect {| rendering... |}];
  Handle.show handle;
  [%expect {| rendering... |}];
  Bonsai.Var.set var 2;
  Handle.show handle;
  [%expect {|
    rendering...
    (change! (prev (1)) (cur 2)) |}];
  Handle.show handle;
  [%expect {| rendering... |}];
  Handle.show handle;
  [%expect {| rendering... |}]
;;

let%expect_test "actor" =
  let print_int_effect = printf "%d\n" |> Bonsai.Effect.of_sync_fun |> unstage in
  let component =
    let%sub _, effect =
      Bonsai.actor0
        [%here]
        (module Int)
        (module Unit)
        ~default_model:0
        ~recv:(fun ~schedule_event:_ v () -> v + 1, v)
    in
    return
    @@ let%map effect = effect in
    Bonsai.Effect.inject_ignoring_response
    @@ let%bind.Bonsai.Effect i = effect () in
    print_int_effect i
  in
  let handle =
    Handle.create
      (module struct
        type t = Event.t
        type incoming = unit

        let view _ = ""
        let incoming t () = t
      end)
      component
  in
  Handle.do_actions handle [ () ];
  Handle.show handle;
  [%expect {| 0 |}];
  Handle.do_actions handle [ (); (); () ];
  Handle.show handle;
  [%expect {|
    1
    2
    3 |}]
;;

let%expect_test "lifecycle" =
  let effect action on =
    Ui_event.print_s [%message (action : string) (on : string)] |> Bonsai.Value.return
  in
  let component input =
    let rendered = Bonsai.const "" in
    if%sub input
    then (
      let%sub () =
        Bonsai.Edge.lifecycle
          ~on_activate:(effect "activate" "a")
          ~on_deactivate:(effect "deactivate" "a")
          ~after_display:(effect "after-display" "a")
          ()
      in
      rendered)
    else (
      let%sub () =
        Bonsai.Edge.lifecycle
          ~on_activate:(effect "activate" "b")
          ~on_deactivate:(effect "deactivate" "b")
          ~after_display:(effect "after-display" "b")
          ()
      in
      rendered)
  in
  let var = Bonsai.Var.create true in
  let handle =
    Handle.create (Result_spec.string (module String)) (component (Bonsai.Var.value var))
  in
  Handle.show handle;
  [%expect {|
    ((action activate) (on a))
    ((action after-display) (on a)) |}];
  Bonsai.Var.set var false;
  Handle.show handle;
  [%expect
    {|
    ((action deactivate) (on a))
    ((action activate) (on b))
    ((action after-display) (on b)) |}];
  Bonsai.Var.set var true;
  Handle.show handle;
  [%expect
    {|
    ((action deactivate) (on b))
    ((action activate) (on a))
    ((action after-display) (on a)) |}]
;;

let%expect_test "Clock.every" =
  let print_hi = (fun () -> print_endline "hi") |> Bonsai.Effect.of_sync_fun |> unstage in
  let component =
    let%sub () =
      Bonsai.Clock.every
        [%here]
        (Time_ns.Span.of_sec 3.0)
        (Bonsai.Value.return (Bonsai.Effect.inject_ignoring_response (print_hi ())))
    in
    Bonsai.const ()
  in
  let handle = Handle.create (Result_spec.sexp (module Unit)) component in
  let move_forward_and_show () =
    Handle.advance_clock_by handle (Time_ns.Span.of_sec 1.0);
    Handle.show handle
  in
  Handle.show handle;
  [%expect {|
    ()
    hi |}];
  move_forward_and_show ();
  [%expect {| () |}];
  move_forward_and_show ();
  [%expect {| () |}];
  move_forward_and_show ();
  [%expect {|
     ()
     hi |}]
;;

let edge_poll_shared ~get_expect_output =
  let effect_tracker = Query_response_tracker.create () in
  let effect =
    unstage @@ Bonsai.Effect.For_testing.of_query_response_tracker effect_tracker
  in
  let var = Bonsai.Var.create "hello" in
  let component =
    Bonsai.Edge.Poll.effect_on_change
      [%here]
      (module String)
      (module String)
      Bonsai.Edge.Poll.Starting.empty
      (Bonsai.Var.value var)
      ~effect:(Bonsai.Value.return effect)
  in
  let handle =
    Handle.create
      (Result_spec.sexp
         (module struct
           type t = string option [@@deriving sexp]
         end))
      component
  in
  let trigger_display () =
    (* Polling is driven by [on_display] callbacks, which is triggered by
       [Handle.show] *)
    Handle.show handle;
    let pending = Query_response_tracker.queries_pending_response effect_tracker in
    let output = Sexp.of_string (get_expect_output ()) in
    print_s [%message (pending : string list) (output : Sexp.t)]
  in
  var, effect_tracker, trigger_display
;;

let%expect_test "Edge.poll in order" =
  let get_expect_output () = [%expect.output] in
  let var, effect_tracker, trigger_display = edge_poll_shared ~get_expect_output in
  trigger_display ();
  [%expect {|
    ((pending ())
     (output  ())) |}];
  trigger_display ();
  [%expect {|
    ((pending (hello)) (output ())) |}];
  Bonsai.Var.set var "world";
  trigger_display ();
  [%expect {|
    ((pending (hello)) (output ())) |}];
  trigger_display ();
  [%expect {|
    ((pending (world hello)) (output ())) |}];
  Query_response_tracker.maybe_respond effect_tracker ~f:(fun s ->
    Respond (String.uppercase s));
  trigger_display ();
  [%expect {| ((pending ()) (output (WORLD))) |}]
;;

(* When completing the requests out-of-order, the last-fired effect still
   wins *)
let%expect_test "Edge.poll out of order" =
  let get_expect_output () = [%expect.output] in
  let var, effect_tracker, trigger_display = edge_poll_shared ~get_expect_output in
  trigger_display ();
  [%expect {|
    ((pending ())
     (output  ())) |}];
  trigger_display ();
  [%expect {|
    ((pending (hello)) (output ())) |}];
  Bonsai.Var.set var "world";
  trigger_display ();
  [%expect {|
    ((pending (hello)) (output ())) |}];
  trigger_display ();
  [%expect {|
    ((pending (world hello)) (output ())) |}];
  Query_response_tracker.maybe_respond effect_tracker ~f:(function
    | "world" as s -> Respond (String.uppercase s)
    | _ -> No_response_yet);
  trigger_display ();
  [%expect {|
    ((pending (hello))
     (output  (WORLD))) |}];
  Query_response_tracker.maybe_respond effect_tracker ~f:(function
    | "hello" as s -> Respond (String.uppercase s)
    | _ -> No_response_yet);
  trigger_display ();
  [%expect {|
    ((pending ()) (output (WORLD))) |}]
;;

let%expect_test "Clock.now" =
  let clock = Incr.Clock.create ~start:Time_ns.epoch () in
  let component = Bonsai.Clock.now in
  let handle =
    Handle.create ~clock (Result_spec.sexp (module Time_ns.Alternate_sexp)) component
  in
  Handle.show handle;
  [%expect {| "1970-01-01 00:00:00Z" |}];
  Incr.Clock.advance_clock_by clock (Time_ns.Span.of_sec 0.5);
  Handle.show handle;
  [%expect {| "1970-01-01 00:00:00.5Z" |}];
  Incr.Clock.advance_clock_by clock (Time_ns.Span.of_sec 0.7);
  Handle.show handle;
  [%expect {| "1970-01-01 00:00:01.2Z" |}]
;;

let%expect_test "Clock.approx_now" =
  let clock = Incr.Clock.create ~start:Time_ns.epoch () in
  let component = Bonsai.Clock.approx_now ~tick_every:(Time_ns.Span.of_sec 1.0) in
  let handle =
    Handle.create ~clock (Result_spec.sexp (module Time_ns.Alternate_sexp)) component
  in
  Handle.show handle;
  [%expect {| "1970-01-01 00:00:00Z" |}];
  Incr.Clock.advance_clock_by clock (Time_ns.Span.of_sec 0.5);
  Handle.show handle;
  [%expect {| "1970-01-01 00:00:00Z" |}];
  Incr.Clock.advance_clock_by clock (Time_ns.Span.of_sec 0.7);
  Handle.show handle;
  [%expect {| "1970-01-01 00:00:01.2Z" |}]
;;
