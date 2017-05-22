#############
# Intercept #
#############

struct Intercept{F} <: Function
    func::F
end

@inline Intercept(i::Intercept) = Intercept(p.func)

@inline (i::Intercept)(input...) = Primitive(promote_genre(input...), p.func)(input...)

#=
works for the following formats:
- `@intercept(f)(args...)`
- `@intercept f(args...) = ...`
- `@intercept function f(args...) ... end`
- `@intercept f = (args...) -> ...`
=#
macro intercept(expr)
    if isa(expr, Expr) && (expr.head == :(=) || expr.head == :function)
        lhs = expr.args[1]
        if isa(lhs, Expr) && lhs.head == :call # named function definition site
            name_and_types = lhs.args[1]
            if isa(name_and_types, Expr) && name_and_types.head == :curly
                old_name = name_and_types.args[1]
                hidden_name = Symbol("#cassette_hidden_$(old_name)")
                name_and_types.args[1] = hidden_name
            elseif isa(name_and_types, Symbol)
                old_name = name_and_types
                hidden_name = Symbol("#cassette_hidden_$(old_name)")
                lhs.args[1] = hidden_name
            else
                error("failed to apply Cassette.Intercept to expression $(expr); potentially malformed function signature?")
            end
            result = quote
                $expr
                if !(isdefined($(Expr(:quote, old_name))))
                    const $(old_name) = $(Intercept)($(hidden_name))
                end
            end
        elseif isa(lhs, Symbol) # variable assignment site
            expr.args[2] = :($(Intercept)($(expr.args[2])))
            result = expr
        else
            error("failed to apply Cassette.Intercept to expression $expr")
        end
    else # call site
        result = :($(Intercept)($expr))
    end
    return esc(result)
end

#############
# Primitive #
#############

struct Primitive{G,F} <: Function
    genre::G
    func::F
end

@inline (p::Primitive)(input...) = error("Primitive execution is not yet defined for genre $(e.genre) and function $(e.func).")

###############################
# Default Primitive Execution #
###############################

@inline untrack_call(f, a) = f(untrack(a))
@inline untrack_call(f, a, b) = f(untrack(a), untrack(b))
@inline untrack_call(f, a, b, c) = f(untrack(a), untrack(b), untrack(c))
@inline untrack_call(f, a, b, c, d) = f(untrack(a), untrack(b), untrack(c), untrack(d))
@inline untrack_call(f, a, b, c, d, e) = f(untrack(a), untrack(b), untrack(c), untrack(d), untrack(e))
@inline untrack_call(f, args...) = f(untrack.(args)...)

@inline function (p::Primitive)(input...)
    output = untrack_call(p.func, input...)
    return maybe_track_output(p, output, input, TrackableTrait(output))
end

# If `output` is `Trackable`, then return a tracked version of it
@inline maybe_track_output(p::Primitive, output, input, ::Trackable) = track(output, p.genre, FunctionNode(p.func, input))

# If `output` is `NotTrackable`, then just return it
@inline maybe_track_output(p::Primitive, output, input, ::NotTrackable) = output
