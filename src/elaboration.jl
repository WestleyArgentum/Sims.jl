
########################################
## Elaboration / flattening           ##
########################################

#
# This converts a hierarchical model into a flat set of equations.
# 
# After elaboration, the following structure is returned. This sort-of
# follows Hydra's SymTab structure.
#

#
type EquationSet
    model             # The active model, a hierachichal set of equations.
    equations         # A flat list of equations.
    initialequations  # A flat list of initial equations.
    events
    pos_responses
    neg_responses
    nodeMap::Dict
end
# In EquationSet, model contains equations and StructuralEvents. When
# a StructuralEvent triggers, the entire model is elaborated again.
# The first step is to replace StructuralEvents that have activated
# with their new_relation in model. Then, the rest of the EquationSet
# is reflattened using model as the starting point.


# 
# elaborate is the main elaboration function. There is no real symbolic
# processing (sorting, index reduction, or any of the other stuff a
# fancy modeling tool would do).
# 
elaborate(a::Model) = elaborate(EquationSet(a, {}, {}, {}, {}, {}, Dict()))

function elaborate(x::EquationSet)
    eq = EquationSet({}, {}, {}, {}, {}, {}, Dict())
    eq.model = handle_events(x.model)
    elaborate_unit(eq.model, eq) # This will modify eq.

    # Add in equations for each node to sum flows to zero:
    for (key, nodeset) in eq.nodeMap
        push!(eq.equations, nodeset)
        push!(eq.initialequations, nodeset)
    end
    # last fixups:
    
    eq.initialequations = replace_fixed(remove_empties(strip_mexpr(eq.initialequations)))
    eq.equations = remove_empties(strip_mexpr(eq.equations))
    eq
end

# Generic model traversing helper.
# Applies a function to each element of the model tree.
function traverse_mod(f::Function, a::Model)
    emodel = {}
    for el in a
        el1 = f(el)
        if isa(el1, Array)
            append!(emodel, el1)
        else  # this handles symbols
            push!(emodel, el1)
        end
    end
    emodel
end

#
# replace_fixed searches through initial equations and replaces
# Unknowns that have a fixed initial value with that value.
#
replace_fixed(a::Model) = map(replace_fixed, a)
replace_fixed(x) = x
replace_fixed(eq::InitialEquation) = InitialEquation(map(replace_fixed, eq.eq))
replace_fixed(a::MExpr) = strip_mexpr(a.ex)
replace_fixed(e::Expr) = Expr(e.head, (isempty(e.args) ? e.args : map(replace_fixed, e.args))...)
replace_fixed(u::Unknown) = u.fixed ? u.value : u

#
# handle_events traverses the model tree and replaces
# StructuralEvent's that have activated.
#
handle_events(a::Model) = traverse_mod(handle_events, a)
handle_events(a::InitialEquation) = a
handle_events(x) = x
handle_events(ev::StructuralEvent) = ev.activated ? ev.new_relation() : ev

#
# elaborate_unit flattens the set of equations while building up
# events, event responses, and a Dict of nodes.
#
elaborate_unit(a::Any, eq::EquationSet) = nothing # The default is to ignore undefined types.
function elaborate_unit(a::ModelType, eq::EquationSet)
    push!(eq.equations, a)
    push!(eq.initialequations, a)
end
function elaborate_unit(a::InitialEquation, eq::EquationSet)
    push!(eq.initialequations, a.eq)
end
function elaborate_unit(a::Model, eq::EquationSet)
    map(x -> elaborate_unit(x, eq), a)
end

function elaborate_unit(b::RefBranch, eq::EquationSet)
    if (isa(b.n, Unknown))
        eq.nodeMap[b.n] = get(eq.nodeMap, b.n, 0.0) + b.i
    elseif (isa(b.n, RefUnknown))
        vec = compatible_values(b.n.u)
        vec[b.n.idx...] = 1.0
        eq.nodeMap[b.n.u] = get(eq.nodeMap, b.n.u, 0.0) + b.i .* vec 
    end
end

elaborate_subunit(a::Any) = Any[] # The default is to ignore undefined types.
elaborate_subunit(a::ModelType) = a
elaborate_subunit(a::Model) = map(x -> elaborate_subunit(x), a)

function elaborate_unit(ev::Event, eq::EquationSet)
    push!(eq.events, strip_mexpr(elaborate_subunit(ev.condition)))
    push!(eq.pos_responses, strip_mexpr(elaborate_subunit(ev.pos_response)))
    push!(eq.neg_responses, strip_mexpr(elaborate_subunit(ev.neg_response)))
end

function elaborate_unit(ev::StructuralEvent, eq::EquationSet)
    # Set up the event:
    push!(eq.events, strip_mexpr(elaborate_subunit(ev.condition)))
    # A positive zero crossing initiates a change:
    push!(eq.pos_responses, (t,y,yp) -> begin global __sim_structural_change = true; ev.activated = true; end)
    # Dummy negative zero crossing
    push!(eq.neg_responses, (t,y,yp) -> return)
    elaborate_unit(ev.default, eq)
end


# These methods strip the MExpr's from expressions.
strip_mexpr(a) = a
strip_mexpr{T}(a::Vector{T}) = map(strip_mexpr, a)
strip_mexpr(a::MExpr) = strip_mexpr(a.ex)
## strip_mexpr(a::MSymbol) = a.sym 
strip_mexpr(e::Expr) = Expr(e.head, (isempty(e.args) ? e.args : map(strip_mexpr, e.args))...)

# Other utilities:
remove_empties(l::Vector{Any}) = filter(x -> !isequal(x, {}), l)
eval_all(x) = eval(x)
eval_all{T}(x::Array{T,1}) = map(eval_all, x)


