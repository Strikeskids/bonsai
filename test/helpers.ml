open! Core_kernel
include Helpers_intf

let make_generic
      (type input model action result s)
      ~(driver : (input, model, s) Driver.t)
      ~sexp_of_result
      ~(get_result : s -> result)
      ~(schedule_action : s -> action -> unit)
  : (module S with type input = input and type model = model and type action = action)
  =
  (module struct
    type nonrec input = input
    type nonrec model = model
    type nonrec action = action

    let show () = print_s ([%sexp_of: result] (get_result (Driver.result driver)))

    let set_input input =
      Driver.set_input driver input;
      Driver.flush driver;
      show ()
    ;;

    let set_model model =
      Driver.set_model driver model;
      Driver.flush driver;
      show ()
    ;;

    let do_actions actions =
      List.iter actions ~f:(schedule_action (Driver.result driver));
      Driver.flush driver;
      show ()
    ;;
  end)
;;

let make ~driver ~sexp_of_result =
  make_generic
    ~driver
    ~sexp_of_result
    ~get_result:Fn.id
    ~schedule_action:(Fn.const Nothing.unreachable_code)
;;

let make_with_inject ~driver ~sexp_of_result =
  make_generic
    ~driver
    ~sexp_of_result
    ~get_result:fst
    ~schedule_action:(fun (_, inject) action ->
      Driver.schedule_event driver (inject action))
;;

let make_string = make ~sexp_of_result:[%sexp_of: string]
let make_string_with_inject = make_with_inject ~sexp_of_result:[%sexp_of: string]
