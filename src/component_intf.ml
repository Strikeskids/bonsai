open! Core_kernel
open! Import

module type S = sig
  module Event : T
  module Incr : Incremental.S

  (** Default is [`Ignore]. *)
  type 'custom mismatch_behavior =
    [ `Ignore
    | `Raise
    | `Warn
    | `Custom of 'custom
    ]

  type ('extra, 'new_model) on_action_mismatch = ('extra -> 'new_model) mismatch_behavior

  (** The component type ([('model, 'result) Bonsai.t]) can be thought of as a
      function from ['model] to ['result], but where the ['result] can schedule events of
      the component's "action type".  These actions are used to produce a new ['model]
      which in turn causes the ['result] to be recomputed. Instances of the ['result] type
      can contain callbacks which schedule actions when interacted with by user (via
      button click, text input, etc). These actions are handled by the component's
      [apply_action] function, which yields a new model to be displayed. *)
  type ('input, 'model, 'result) t

  type ('input, 'model, 'result) nonexpert_t := ('input, 'model, 'result) t

  (** {1 Component Constructors} *)

  (** Returns a component with no action or model, only a constant result. *)
  val const : 'result -> (_, _, 'result) t

  (** A pure function with no model from 'input to 'result *)
  val pure : f:('input -> 'result) -> ('input, _, 'result) t

  (** Like [pure], but gets the input from the ['model]. *)
  val pure_from_model : f:('model -> 'result) -> (_, 'model, 'result) t

  (** [compose a b] joins [a] and [b] together such that the result of [a] is used as the
      input of [b]. *)
  val compose : ('i1, 'model, 'r1) t -> ('r1, 'model, 'r2) t -> ('i1, 'model, 'r2) t

  module Infix : sig
    (** [a >>> b] is [compose a b] *)
    val ( >>> ) : ('i1, 'model, 'r1) t -> ('r1, 'model, 'r2) t -> ('i1, 'model, 'r2) t

    val ( >>| ) : ('input, 'model, 'r1) t -> ('r1 -> 'r2) -> ('input, 'model, 'r2) t
    val ( @>> ) : ('i1 -> 'i2) -> ('i2, 'model, 'result) t -> ('i1, 'model, 'result) t
  end

  (** For composing components which share the same model.  For example, applying an
      action in one component changes the shared model, which is reflected in the results
      of the other component. *)
  include
    Applicative.S3 with type ('r, 'i, 'm) t := ('i, 'm, 'r) t

  (** Transforms the input of a component. The signature of [f] is reversed from most
      other map functions. *)
  val map_input : ('i2, 'model, 'result) t -> f:('i1 -> 'i2) -> ('i1, 'model, 'result) t

  include Applicative.Let_syntax3 with type ('r, 'i, 'm) t := ('i, 'm, 'r) t

  module Let_syntax : sig
    val return : 'result -> (_, _, 'result) t

    include module type of Infix

    module Let_syntax : sig
      val return : 'result -> (_, _, 'result) t
      val map : ('input, 'model, 'r1) t -> f:('r1 -> 'r2) -> ('input, 'model, 'r2) t

      val both
        :  ('input, 'model, 'r1) t
        -> ('input, 'model, 'r2) t
        -> ('input, 'model, 'r1 * 'r2) t

      module Open_on_rhs : sig end
    end
  end

  (** Many modules have the same shape, they declare the model, action, and result of the
      component, and then define apply_action and view over those types.

      This is intended to be used with the [Component.of_module] function. *)
  module type S = sig
    module Input : T
    module Model : T

    module Action : sig
      type t [@@deriving sexp_of]
    end

    module Result : T

    (** [apply_action] is a transformation from a model and an action into a new model.
        During the transformation, the Component can also emit more actions via
        [schedule_event] or use Async to arrange for [schedule_event] to be called later.
    *)
    val apply_action
      :  inject:(Action.t -> Event.t)
      -> schedule_event:(Event.t -> unit)
      -> Input.t
      -> Model.t
      -> Action.t
      -> Model.t

    (** Computes the [Result.t] of the component based off of the [Model.t].

        The [inject] argument is used to transform actions into [Event.t]s for use in
        event handlers like [on_click]. *)
    val compute : inject:(Action.t -> Event.t) -> Input.t -> Model.t -> Result.t

    (** A name to identify this component.

        A reasonable fallback is [Source_code_position.to_string [%here]]. *)
    val name : string
  end

  type ('input, 'model, 'action, 'result) component_s =
    (module S
      with type Input.t = 'input
       and type Model.t = 'model
       and type Action.t = 'action
       and type Result.t = 'result)

  module M (Component : S) : sig
    type nonrec t = (Component.Input.t, Component.Model.t, Component.Result.t) t
  end

  (** Creates a component from a [Component.S] first class module. *)
  val of_module
    :  ('input, 'model, 'action, 'result) component_s
    -> ('input, 'model, 'result) t

  module Incremental : sig
    (** Constructs a bonsai component whose result is always 
        the same as its input Incremental node.  *)
    val of_incr : 'result Incr.t -> (_, _, 'result) t

    (** Same as [Bonsai.pure] but allows the user to optimize using Incremental. *)
    val pure : f:('input Incr.t -> 'result Incr.t) -> ('input, _, 'result) t

    (** Same as [Bonsai.pure_from_model], but allows the user to optimize using Incremental. *)
    val pure_from_model : f:('model Incr.t -> 'result Incr.t) -> (_, 'model, 'result) t

    (** Transforms the result of a component, exposing the incrementality for optimization
        purposes. *)
    val map
      :  ('input, 'model, 'r1) t
      -> f:('r1 Incr.t -> 'r2 Incr.t)
      -> ('input, 'model, 'r2) t

    (** Transforms the input of a component, exposing the incrementality for optimization
        purposes. The signature of [f] is reversed from most other map functions. *)
    val map_input
      :  ('i2, 'model, 'result) t
      -> f:('i1 Incr.t -> 'i2 Incr.t)
      -> ('i1, 'model, 'result) t

    module Case : sig
      type ('input, 'outer_model, 'result) case

      type ('outer_input, 'outer_model, 'result) case_creator =
        { create_case :
            'inner_input 'inner_model. ('inner_input, 'inner_model, 'result) t
            -> case_input:'inner_input Incr.t -> case_model:'inner_model Incr.t
            -> lift:('inner_model -> 'outer_model)
            -> ('outer_input, 'outer_model, 'result) case Incr.t
        }
    end

    (** [switch] is a function designed to be used in conjunction with [ppx_pattern_bind]
        in order to provide dynamic switching between components based on a variant.

        The [f] argument takes a [case_creator] which contains a field named [create_case]
        which can be used on the right-hand side of a [match] to handle that case.

        The [create_case] function takes four arguments
        - The component for that case;
        - The input for that component;
        - The model for that component (either the input or model is typically the pattern
          variable that was bound in this match-arm);
        - A [lift]ing function that re-wraps the model in a way that promotes changes to
          the model back to the outer variant model.

        Here is an example usage that changes components based on the model. With a small
        change, the input instead could be used to switch components.

        {[
          let my_component = switch ~f:(fun { create_case } input model  ->
            let open Incr.Let_syntax in
            match%pattern_bind model with
            | Nullary_variant ->
              create_case
                component_a
                ~case_input:input
                ~case_model:(Incr.return ())
                ~lift:(fun () -> Nullary_variant)
            | Unary_variant submodel ->
              create_case
                component_b
                ~case_input:input
                ~case_model:submodel
                ~lift:(fun submodel -> Unary_variant submodel))
        ]}
    *)
    val switch
      :  f:(('outer_input, 'outer_model, 'result) Case.case_creator
            -> 'outer_input Incr.t
            -> 'outer_model Incr.t
            -> ('outer_input, 'outer_model, 'result) Case.case Incr.t)
      -> ('outer_input, 'outer_model, 'result) t

    module type S = sig
      module Input : T
      module Model : T

      module Action : sig
        type t [@@deriving sexp_of]
      end

      module Result : T

      val apply_action
        :  Input.t Incr.t
        -> Model.t Incr.t
        -> inject:(Action.t -> Event.t)
        -> (schedule_event:(Event.t -> unit) -> Action.t -> Model.t) Incr.t

      val compute
        :  Input.t Incr.t
        -> Model.t Incr.t
        -> inject:(Action.t -> Event.t)
        -> Result.t Incr.t

      (** A name to identify this component.

          A reasonable fallback is [Source_code_position.to_string [%here]]. *)
      val name : string
    end

    type ('input, 'model, 'action, 'result) component_s =
      (module S
        with type Input.t = 'input
         and type Model.t = 'model
         and type Action.t = 'action
         and type Result.t = 'result)

    val of_module
      :  ('input, 'model, 'action, 'result) component_s
      -> ('input, 'model, 'result) t
  end

  module Expert : sig
    (** The underlying representations of Bonsai components.  This module is provided "as
        is", without warranty of any kind, express or implied... *)
    module Snapshot : Snapshot.S with module Event := Event

    (** [unpacked] exposes the action type of a component as an existential. *)
    type ('input, 'model, 'action, 'result) unpacked

    (** Every Bonsai component has a hidden ['action] type, which can be revealed as an
        existential by pattern matching on {!t}. *)
    type ('input, 'model, 'result) t = private
      | T :
          ('input, 'model, 'action, 'result) unpacked * 'action Type_equal.Id.t
          -> ('input, 'model, 'result) t

    (** [reveal t] is just the identity, but it allows you to pattern match on the GADT to
        get the unpacked component (which you can [eval]) and the action's type ID. *)
    val reveal : ('input, 'model, 'result) nonexpert_t -> ('input, 'model, 'result) t

    (** [conceal] is the inverse of [reveal]. *)
    val conceal : ('input, 'model, 'result) t -> ('input, 'model, 'result) nonexpert_t


    (** Builds a component out of the incremental function from ['model Incr.t] to
        [Snapshot.t Incr.t]. This function is in the expert module because it is
        effectively a black box to the rest of the Bonsai library, which means [optimize]
        cannot do anything with it, for example. *)
    val of_full
      :  f:(input:'input Incr.t
            -> old_model:'model option Incr.t
            -> model:'model Incr.t
            -> inject:('action -> Event.t)
            -> ('model, 'action, 'result) Snapshot.t Incr.t)
      -> action_type_id:'action Type_equal.Id.t
      -> ('input, 'model, 'result) t

    (*_ Do you like GADT's? I do. That's why this function is called [eval], and not
      something that is more informative. Gotta keep those traditions alive somehow. *)

    (** Walks the component tree and builds a [Snapshot.t Incr.t] which will be recomputed
        when [model] and [old_model] change. *)
    val eval
      :  input:'input Incr.t
      -> old_model:'model option Incr.t
      -> model:'model Incr.t
      -> inject:('action -> Event.t)
      -> action_type_id:'action Type_equal.Id.t
      -> ('input, 'model, 'action, 'result) unpacked
      -> ('model, 'action, 'result) Snapshot.t Incr.t

    (** Performs constant-folding and other optimizations on the component tree. This
        function is called once-per-component tree, which should be roughly
        once-per-application life-cycle unless there is dynamic component tree creation
        going on (perhaps via [of_full] and [eval]). *)
    val optimize : ('input, 'model, 'result) t -> ('input, 'model, 'result) t
  end

  (** {1 Combinators} *)

  module Project : sig
    module Model : sig
      val f
        :  ('input, 'm1, 'result) t
        -> unlift:('m2 -> 'm1)
        -> lift:('m2 -> 'm1 -> 'm2)
        -> ('input, 'm2, 'result) t

      val ignore : ('input, unit, 'result) t -> ('input, 'model, 'result) t

      val field
        :  ('model_outer, 'model_inner) Field.t
        -> ('input, 'model_inner, 'result) t
        -> ('input, 'model_outer, 'result) t

      (** Takes a component that operates immutably over an input (via 'input), and
          converts it to a component that gets its input from the model. *)
      val to_input : ('input, unit, 'result) t -> (unit, 'input, 'result) t

      (** Takes a component that operates immutably over an input (via 'input), and
          converts it to a component that gets part of that input from the model. *)
      val to_input_with_other
        :  ('input * 'model, unit, 'result) t
        -> ('input, 'model, 'result) t
    end
  end

  module Map : sig
    (** Transforms a component into a new component whose model and result are maps. *)
    val assoc_model
      :  ?comparator:('k, 'cmp) Map.comparator
      -> ('input, 'model, 'result) t
      -> ('input, ('k, 'model, 'cmp) Map.t, ('k, 'result, 'cmp) Map.t) t

    (** Transforms a component into a new component whose model and result are maps.  The
        input for the transformed component also receives its key as an input. *)
    val associ_model
      :  ?comparator:('k, 'cmp) Map.comparator
      -> ('k * 'input, 'model, 'result) t
      -> ('input, ('k, 'model, 'cmp) Map.t, ('k, 'result, 'cmp) Map.t) t

    (** Transforms a component into a new component whose input and result are maps. *)
    val assoc_input
      :  ?comparator:('k, 'cmp) Map.comparator
      -> ('input, 'model, 'result) t
      -> (('k, 'input, 'cmp) Map.t, 'model, ('k, 'result, 'cmp) Map.t) t

    (** Transforms a component into a new component whose input and result are maps.
        The input for the transformed component also receives its key as an input.  *)
    val associ_input
      :  ?comparator:('k, 'cmp) Map.comparator
      -> ('k * 'input, 'model, 'result) t
      -> (('k, 'input, 'cmp) Map.t, 'model, ('k, 'result, 'cmp) Map.t) t

    (** Given two components that produce maps, create a new component that produces a map
        that is merged according provided function [f]. *)
    val merge
      :  ('input, 'model, ('k, 'r1, 'cmp) Base.Map.t) t
      -> ('input, 'model, ('k, 'r2, 'cmp) Base.Map.t) t
      -> f:(key:'k
            -> [ `Both of 'r1 * 'r2 | `Left of 'r1 | `Right of 'r2 ]
            -> 'result option)
      -> ('input, 'model, ('k, 'result, 'cmp) Base.Map.t) t
  end

  module Option : sig
    val wrap_model
      :  ?on_action_for_none:(unit, 'model option) on_action_mismatch
      -> ('input, 'model, 'result) t
      -> ('input, 'model option, 'result option) t

    val wrap_model_with_default
      :  ?on_action_for_none:(unit, 'model option) on_action_mismatch
      -> ('input, 'model, 'result) t
      -> default:'result
      -> ('input, 'model option, 'result) t

  end

  module Either : sig
    val wrap_model
      :  ?on_action_for_other_component:( [ `Action_for_first of 'm2
                                          | `Action_for_second of 'm1
                                          ]
                                        , ('m1, 'm2) Either.t )
           on_action_mismatch
      -> ('input, 'm1, 'r1) t
      -> ('input, 'm2, 'r2) t
      -> ('input, ('m1, 'm2) Either.t, ('r1, 'r2) Either.t) t

    val wrap_model_with_same_result
      :  ?on_action_for_other_component:( [ `Action_for_first of 'm2
                                          | `Action_for_second of 'm1
                                          ]
                                        , ('m1, 'm2) Either.t )
           on_action_mismatch
      -> ('input, 'm1, 'r) t
      -> ('input, 'm2, 'r) t
      -> ('input, ('m1, 'm2) Either.t, 'r) t

  end

  module List_deprecated : sig
    (** Projecting over lists in Bonsai is fraught with issues.
        1. Incremental can't be optimized for linked-list data structures.
        2. Using list-index as the method for routing actions to components is basically
        never what you actually want, causing mis-delivery of events every time that the
        list changes. *)
  end
end

module type Component = sig
  module type S = S

  (** Bonsai can be used with any Incremental-style UI framework. The parameters for the
      Bonsai component functor are an instance of Incremental (used to re-evaluate the UI
      only when the UI model has changed) and an opaque Event.t type (which is used to
      schedule actions). *)
  module Make (Incr : Incremental.S) (Event : T) :
    S with module Incr := Incr with module Event := Event
end
