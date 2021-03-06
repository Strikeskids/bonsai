open! Core_kernel
open! Import
module Bonsai_lib = Bonsai
open Proc

module Choice = struct
  type t =
    | Homepage
    | Loading
    | Search_results
  [@@deriving sexp, equal]
end

let apply_action ~inject ~schedule_event _ _ new_page =
  (match new_page with
   | Choice.Homepage | Search_results -> ()
   | Loading -> schedule_event (inject Choice.Search_results));
  new_page
;;

module Result = struct
  type t =
    { view : string
    ; incoming : Choice.t -> Ui_event.t
    }
  [@@deriving fields]

  type incoming = Choice.t
end

let%expect_test _ =
  let open Bonsai.Let_syntax in
  let graph =
    let%sub state_machine =
      Bonsai.state_machine1
        [%here]
        (module Choice)
        (module Choice)
        ~default_model:Choice.Homepage
        ~apply_action
        (Bonsai.Value.return ())
    in
    let%sub current_page =
      Bonsai.read
        (let%map current_page, _ = state_machine in
         current_page)
    in
    let%sub incoming =
      Bonsai.read
        (let%map _, incoming = state_machine in
         incoming)
    in
    let as_eithers =
      match%map current_page with
      | Loading -> First (Second ())
      | Homepage -> First (Second ())
      | Search_results -> Second ()
    in
    let%sub body =
      (Bonsai.match_either
         as_eithers
         ~first:
           (Bonsai.match_either
              ~first:(fun _ -> Bonsai.const "1")
              ~second:(fun _ -> Bonsai.const "2"))
         ~second:(fun _ -> Bonsai.const "3") [@alert "-deprecated"])
    in
    Bonsai.read
      (let%map view = body
       and incoming = incoming in
       { Result.view; incoming })
  in
  let handle = Handle.create (module Result) graph in
  Handle.show handle;
  [%expect {| 2 |}];
  Handle.do_actions handle [ Search_results ];
  Handle.show handle;
  [%expect {| 3 |}]
;;
