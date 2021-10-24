#--------------------
#--------------------
#### Symbolic
#--------------------
abstract type Symbolic end

###
### Uni-type design
###

@enum ValueType::UInt8 BOOL INT RATIONAL REAL NUMBER
@enum ExprType::UInt8  SYM TERM ADD MUL POW DIV

const Metadata = Union{Nothing,Base.ImmutableDict{DataType,Any}}
const NO_METADATA = nothing

# flags
const ARRAY = 0x01
const COMPLEX = 0x01 << 1
const SIMPLIFIED = 0x01 << 2

sdict(kv...) = Dict{Any, Any}(kv...)

using Base: RefValue
const EMPTY_ARGS = []
const EMPTY_HASH = RefValue(UInt(0))
const EMPTY_DICT = sdict()
const EMPTY_DICT_T = typeof(EMPTY_DICT)

# IT IS IMPORTANT TO MAKE SURE ANYS ARE ANY!!!
#
# Also, try to union split
Base.@kwdef struct BasicSymbolic <: Symbolic
    valtype::ValueType     = REAL
    exprtype::ExprType     = TERM
    bitflags::UInt8        = 0x00
    # Sym
    name::Symbol           = :OOF
    # Term
    f::Any                 = identity  # base/num if Pow; issorted if Add/Dict
    arguments::Vector{Any} = EMPTY_ARGS
    # Mul/Add
    coeff::Any             = 0         # exp/den if Pow
    dict::EMPTY_DICT_T     = EMPTY_DICT
    hash::RefValue{UInt}   = EMPTY_HASH
    metadata::Metadata     = NO_METADATA
end

@inline function Base.getproperty(x::BasicSymbolic, s::Symbol)
    (s === :metadata || s === :hash || s === :arguments) && return getfield(x, s)
    E = exprtype(x)
    if (E === SYM && s === :name) ||
        (E === TERM && s === :f) ||
        ((E === ADD || E === MUL) && (s === :coeff || s === :dict))
        getfield(x, s)
    elseif E === DIV
        s === :num ? getfield(x, :f) :
        s === :den ? getfield(x, :coeff) :
        error_property(E, s)
    elseif E === POW
        s === :base ? getfield(x, :f) :
        s === :exp ? getfield(x, :coeff) :
        error_property(E, s)
    elseif (E === ADD || E === MUL) && s === :issorted
        getfield(x, :f)::RefValue{Bool}
    else
        error_property(E, s)
    end
end

@inline function valtype2type(T::ValueType)
    T === NUMBER ? Number :
    T === REAL ? Real :
    T === RATIONAL ? Rational :
    T === INT ? Int :
    Bool
end

@noinline error_no_valtype(T) = error("$T is not supported.")
@noinline error_on_type(E) = error("Internal error: type $E not handled!")
@noinline error_sym() = error("Sym doesn't have a operation or arguments!")
@noinline error_property(E, s) = error("$E doesn't have field $s")

@inline function type2valtype(@nospecialize T)
    T === Number ? NUMBER :
    T === Real ? REAL :
    T === Rational ? RATIONAL :
    T === Int ? INT :
    T === Bool ? BOOL :
    error_no_valtype(T)
end

@inline is_of_type(x::BasicSymbolic, type::UInt8) = (x.bitflags & type) != 0x00
@inline isarray(x::BasicSymbolic) = is_of_type(x, ARRAY)
@inline iscomplex(x::BasicSymbolic) = is_of_type(x, COMPLEX)
@inline issimplified(x::BasicSymbolic) = is_of_type(x, SIMPLIFIED)

@inline function valtype(x)
    if x isa BasicSymbolic
        getfield(x, :valtype)
    elseif x isa Union{Int, Bool}
        type2valtype(typeof(x))
    elseif x isa Rational
        RATIONAL
    else
        REAL
    end
end
@inline exprtype(x::BasicSymbolic) = getfield(x, :exprtype)

###
### TermInterface
###
using TermInterface

TermInterface.exprhead(x::Symbolic) = :call
TermInterface.symtype(x::Number) = typeof(x)
TermInterface.symtype(::Symbolic) = Any
@inline TermInterface.symtype(s::BasicSymbolic) = valtype2type(valtype(s))

@inline function TermInterface.operation(x::BasicSymbolic)
    E = exprtype(x)
    E === TERM ? getfield(x, :f) :
    E === ADD ? (+) :
    E === MUL ? (*) :
    E === DIV ? (/) :
    E === POW ? (^) :
    E === SYM ? error_sym() :
    error_on_type(E)
end

function TermInterface.arguments(x::BasicSymbolic)
    args = unsorted_arguments(x)
    E = exprtype(x)
    if (E === ADD || E === MUL) && x.issorted[]
        sort!(args, lt = <ₑ)
        x.issorted[] = true
    end
    return args
end
function TermInterface.unsorted_arguments(x::BasicSymbolic)
    E = exprtype(x)
    if E === TERM
        return getfield(x, :arguments)
    elseif E === ADD || E === MUL
        args = x.arguments
        isempty(args) || return args
        siz = length(x.dict)
        iszerocoeff = iszero(x.coeff)
        sizehint!(args, iszerocoeff ? siz : siz + 1)
        iszerocoeff || push!(args, x.coeff)
        if E === ADD
            for (k, v) in x.dict
                push!(args, k * v)
            end
        else # MUL
            for (k, v) in x.dict
                push!(args, unstable_pow(k, v))
            end
        end
        return args
    elseif E === DIV
        args = x.arguments
        isempty(args) || return args
        sizehint!(args, 2)
        push!(args, numerators(x))
        push!(args, denominators(x))
        return args
    elseif E === POW
        args = x.arguments
        isempty(args) || return args
        sizehint!(args, 2)
        push!(args, getbase(x))
        push!(args, getexp(x))
        return args
    elseif E === SYM
        error_sym()
    else
        error_on_type(E)
    end
end

TermInterface.istree(s::BasicSymbolic) = !issym(s)
TermInterface.issym(s::BasicSymbolic) = exprtype(s) === SYM
isterm(x) = x isa BasicSymbolic && exprtype(x) === TERM
ismul(x)  = x isa BasicSymbolic && exprtype(x) === MUL
isadd(x)  = x isa BasicSymbolic && exprtype(x) === ADD
ispow(x)  = x isa BasicSymbolic && exprtype(x) === POW
isdiv(x)  = x isa BasicSymbolic && exprtype(x) === DIV

###
### Base interface
###

Base.isequal(::Symbolic, x) = false
Base.isequal(x, ::Symbolic) = false
Base.isequal(::Symbolic, ::Symbolic) = false

function Base.isequal(a::BasicSymbolic, b::BasicSymbolic)
    a === b && return true

    E = exprtype(a)
    E === exprtype(b) || return false

    T = valtype(a)
    T === valtype(b) || return false

    if E === SYM
        nameof(a) === nameof(b)
    elseif E === ADD || E === MUL
        a.coeff == b.coeff && isequal(a.dict, b.dict)
    elseif E === DIV
        isequal(numerators(a), numerators(b)) && isequal(denominators(a), denominators(b))
    elseif E === POW
        isequal(getexp(a), getexp(b)) && isequal(getbase(a), getbase(b))
    elseif E === TERM
        a1 = arguments(a)
        a2 = arguments(b)
        isequal(operation(a), operation(b)) &&
            length(a1) == length(a2) &&
            all(isequal(l, r) for (l, r) in zip(a1, a2))
    else
        error_on_type(E)
    end
end

Base.one( s::Symbolic) = one( symtype(s))
Base.zero(s::Symbolic) = zero(symtype(s))

Base.nameof(s::BasicSymbolic) = issym(s) ? s.name : error("None Sym BasicSymbolic doesn't have a name")

## This is much faster than hash of an array of Any
hashvec(xs, z) = foldr(hash, xs, init=z)
function Base.hash(s::BasicSymbolic, salt::UInt)
    E = exprtype(s)
    T = valtype(s)
    if E === SYM
        hash(T, hash(nameof(s), salt ⊻ 0x4de7d7c66d41da43))
    elseif E === ADD || E === MUL
        !iszero(salt) && return hash(hash(s, zero(UInt64)), salt)
        h = s.hash[]
        !iszero(h) && return h
        hashoffset = s isa Add ? 0xaddaddaddaddadda : 0xaaaaaaaaaaaaaaaa
        h′= hash(hashoffset, hash(s.coeff, hash(s.dict, salt)))
        s.hash[] = h′
        return h′
    elseif E === DIV
        return hash(numerators(s), hash(denominators(s), salt ⊻ 0x334b218e73bbba53))
    elseif E === POW
        hash(getexp(s), hash(getbase(s), salt ⊻ 0x2b55b97a6efb080c))
    elseif E === TERM
        !iszero(salt) && return hash(hash(s, zero(UInt)), salt)
        h = s.hash[]
        !iszero(h) && return h
        h′ = hashvec(arguments(s), hash(operation(s), hash(T, salt)))
        s.hash[] = h′
        return h′
    else
        error_on_type(E)
    end
end

###
### Constructors
###

for C in [:Sym, :Term, :Mul, :Add, :Pow, :Div]
    @eval struct $C{T} 1+1 end
end

Term{T}(f, args::Vector{Any}; kw...) where T = BasicSymbolic(;
    exprtype=TERM, f=f, arguments=args,
    hash=Ref(UInt(0)),
    valtype=T isa ValueType ? T : type2valtype(T),
    kw...)
Sym{T}(name::Symbol; kw...) where T = BasicSymbolic(;
    exprtype=SYM, name=name,
    valtype=T isa ValueType ? T : type2valtype(T),
    kw...)
getbase(x::BasicSymbolic) = (@assert exprtype(x) === POW; x.base)
getexp(x::BasicSymbolic) = (@assert exprtype(x) === POW; x.exp)

divt(T, num, den; simplified=false, kw...) = BasicSymbolic(;
    exprtype=DIV, f=num, coeff=den,
    valtype=T isa ValueType ? T : type2valtype(T),
    bitflags=simplified ? SIMPLIFIED : 0x00,
    arguments=[],
    kw...)


function Div(n, d, simplified=false; metadata=nothing)
    T = max(valtype(n), valtype(d), RATIONAL)
    _iszero(n) && return zero(typeof(n))
    _isone(d) && return n

    if isdiv(n) && isdiv(d)
        return divt(T, numerators(n) * denominators(d), denominators(n) * numerators(d))
    elseif isdiv(n)
        return divt(T, numerators(n), denominators(n) * d)
    elseif isdiv(d)
        return divt(T, n * denominators(d), numerators(d))
    end

    d isa Number && _isone(-d) && return -1 * n
    n isa Rat && d isa Rat && return n // d # maybe called by oblivious code in simplify

    # GCD coefficient upon construction
    rat, nc = ratcoeff(n)
    if rat
        rat, dc = ratcoeff(d)
        if rat
            g = gcd(nc, dc) * sign(dc) # make denominators positive
            invdc = ratio(1, g)
            n = maybe_intcoeff(invdc * n)
            d = maybe_intcoeff(invdc * d)
        end
    end

    divt(T, n, d; simplified=simplified, metadata=metadata)
end

function Term(f, args; metadata=NO_METADATA)
    T = type2valtype(_promote_symtype(f, args))
    Term{T}(f, args, metadata=metadata)
end

"""
    makeadd(sign, coeff::Number, xs...)

Any Muls inside an Add should always have a coeff of 1
and the key (in Add) should instead be used to store the actual coefficient
"""
function makeadd(sign, coeff, xs...)
    d = sdict()
    for x in xs
        if x isa Add
            coeff += x.coeff
            _merge!(+, d, x.dict, filter=_iszero)
            continue
        end
        if x isa Number
            coeff += x
            continue
        end
        if x isa Mul
            k = Mul(symtype(x), 1, x.dict)
            v = sign * x.coeff + get(d, k, 0)
        else
            k = x
            v = sign + get(d, x, 0)
        end
        if iszero(v)
            delete!(d, k)
        else
            d[k] = v
        end
    end
    coeff, d
end

function Add(T, coeff, dict; metadata=NO_METADATA, kw...)
    if isempty(dict)
        return coeff
    elseif _iszero(coeff) && length(dict) == 1
        k,v = first(dict)
        return _isone(v) ? k : Mul(T, makemul(v, k)...)
    end

    BasicSymbolic(;
                  exprtype=ADD, coeff=coeff, dict=dict,
                  f=Ref(false),
                  hash=Ref(UInt(0)),
                  valtype=T isa ValueType ? T : type2valtype(T),
                  arguments=[],
                  kw...)
end

function makemul(coeff, xs...; d=sdict())
    for x in xs
        if x isa Pow && x.exp isa Number
            d[x.base] = x.exp + get(d, x.base, 0)
        elseif x isa Number
            coeff *= x
        elseif x isa Mul
            coeff *= x.coeff
            _merge!(+, d, x.dict, filter=_iszero)
        else
            v = 1 + get(d, x, 0)
            if _iszero(v)
                delete!(d, x)
            else
                d[x] = v
            end
        end
    end
    (coeff, d)
end

unstable_pow(a, b) = a isa Integer && b isa Integer ? (a//1) ^ b : a ^ b

function Mul(T, a, b; metadata=NO_METADATA, kw...)
    isempty(b) && return a
    if _isone(a) && length(b) == 1
        pair = first(b)
        if _isone(last(pair)) # first value
            return first(pair)
        else
            return unstable_pow(first(pair), last(pair))
        end
    else
        coeff = a
        dict = b
        BasicSymbolic(;
                      exprtype=MUL, coeff=coeff, dict=dict,
                      f=Ref(false),
                      hash=Ref(UInt(0)),
                      valtype=T isa ValueType ? T : type2valtype(T),
                      arguments=[],
                      kw...)
    end
end

function makepow(a, b)
    base = a
    exp = b
    if a isa Pow
        base = a.base
        exp = a.exp * b
    end
    return (base, exp)
end

function Pow(a, b; metadata=NO_METADATA, kw...)
    T = max(valtype(a), valtype(b), BOOL)
    base = a
    exp = b
    _iszero(exp) && return 1
    _isone(exp) && return base
    BasicSymbolic(;
                  exprtype=POW, f=base, coeff=exp,
                  valtype=T,
                  arguments=[],
                  kw...)
end

@inline function numerators(x::BasicSymbolic)
    exprtype(x) === DIV && return x.num
    istree(x) && operation(x) == (*) ? arguments(x) : Any[x]
end

@inline denominators(x::BasicSymbolic) = exprtype(x) === DIV ? x.den : Any[1]

function term(f, args...; type = nothing)
    if type === nothing
        T = _promote_symtype(f, args)
    else
        T = type
    end
    Term{T}(f, Any[args...])
end

"""
    similarterm(t, f, args, symtype; metadata=nothing)

Create a term that is similar in type to `t`. Extending this function allows packages
using their own expression types with SymbolicUtils to define how new terms should
be created. Note that `similarterm` may return an object that has a
different type than `t`, because `f` also influences the result.

## Arguments

- `t` the reference term to use to create similar terms
- `f` is the operation of the term
- `args` is the arguments
- The `symtype` of the resulting term. Best effort will be made to set the symtype of the
  resulting similar term to this type.
"""
TermInterface.similarterm(t::Type{<:Symbolic}, f, args; metadata=nothing, exprhead=:call) =
    similarterm(t, f, args, _promote_symtype(f, args); metadata=metadata, exprhead=exprhead)

function TermInterface.similarterm(t::Type{<:BasicSymbolic}, f, args, symtype; metadata=nothing, exprhead=:call)
    T = symtype
    if T === nothing
        T = _promote_symtype(f, args)
    end
    if f === (+)
        Add(T, makeadd(1, 0, args...)...; metadata=metadata)
    elseif f == (*)
        Mul(T, makemul(1, args...)...; metadata=metadata)
    elseif f == (/)
        @assert length(args) == 2
        Div(args...; metadata=metadata)
    elseif f == (^) && length(args) == 2
        Pow(makepow(args...)...; metadata=metadata)
    else
        Term{T}(f, args; metadata=metadata)
    end
end

###
### Tree print
###

import AbstractTrees

struct TreePrint
    op
    x
end
AbstractTrees.children(x::Union{Term, Pow}) = arguments(x)
function AbstractTrees.children(x::Union{Add, Mul})
    children = Any[x.coeff]
    for (key, coeff) in pairs(x.dict)
        if coeff == 1
            push!(children, key)
        else
            push!(children, TreePrint(x isa Add ? (:*) : (:^), (key, coeff)))
        end
    end
    return children
end
AbstractTrees.children(x::TreePrint) = [x.x[1], x.x[2]]

print_tree(x; show_type=false, maxdepth=Inf, kw...) = print_tree(stdout, x; show_type=show_type, maxdepth=maxdepth, kw...)
function print_tree(_io::IO, x::Union{Term, Add, Mul, Pow, Div}; show_type=false, kw...)
    AbstractTrees.print_tree(_io, x; withinds=true, kw...) do io, y, inds
        if istree(y)
            print(io, operation(y))
        elseif y isa TreePrint
            print(io, "(", y.op, ")")
        else
            print(io, y)
        end
        if !(y isa TreePrint) && show_type
            print(io, " [", typeof(y), "]")
        end
    end
end

TermInterface.istree(t::Type{<:Sym}) = false
TermInterface.istree(t::Type{<:Symbolic}) = true

###
### Metadata
###
using Setfield
@generated function Setfield.getproperties(obj::BasicSymbolic)
    fnames = fieldnames(obj)
    fvals = map(fnames) do fname
        Expr(:call, :getfield, :obj, QuoteNode(fname))
    end
    fvals = Expr(:tuple, fvals...)
    :(NamedTuple{$fnames}($fvals))
end
TermInterface.metadata(s::Symbolic) = s.metadata
TermInterface.metadata(s::Symbolic, meta) = Setfield.@set! s.metadata = meta

function hasmetadata(s::Symbolic, ctx)
    metadata(s) isa AbstractDict && haskey(metadata(s), ctx)
end

function getmetadata(s::Symbolic, ctx)
    md = metadata(s)
    if md isa AbstractDict
        md[ctx]
    else
        throw(ArgumentError("$s does not have metadata for $ctx"))
    end
end

function getmetadata(s::Symbolic, ctx, default)
    md = metadata(s)
    md isa AbstractDict ? get(md, ctx, default) : default
end

# pirated for Setfield purposes:
using Base: ImmutableDict
Base.ImmutableDict(d::ImmutableDict{K,V}, x, y)  where {K, V} = ImmutableDict{K,V}(d, x, y)

assocmeta(d::Dict, ctx, val) = (d=copy(d); d[ctx] = val; d)
function assocmeta(d::Base.ImmutableDict, ctx, val)::ImmutableDict{DataType,Any}
    # optimizations
    # If using upto 3 contexts, things stay compact
    if isdefined(d, :parent)
        d.key === ctx && return @set d.value = val
        d1 = d.parent
        if isdefined(d1, :parent)
            d1.key === ctx && return @set d.parent.value = val
            d2 = d1.parent
            if isdefined(d2, :parent)
                d2.key === ctx && return @set d.parent.parent.value = val
            end
        end
    end
    Base.ImmutableDict{DataType, Any}(d, ctx, val)
end

function setmetadata(s::Symbolic, ctx::DataType, val)
    if s.metadata isa AbstractDict
        @set s.metadata = assocmeta(s.metadata, ctx, val)
    else
        # fresh Dict
        @set s.metadata = Base.ImmutableDict{DataType, Any}(ctx, val)
    end
end

function to_symbolic(x)
    Base.depwarn("`to_symbolic(x)` is deprecated, define the interface for your " *
                 "symbolic structure using `istree(x)`, `operation(x)`, `arguments(x)` " *
                 "and `similarterm(::YourType, f, args, symtype)`", :to_symbolic, force=true)

    x
end

###
###  Pretty printing
###
const show_simplified = Ref(false)

Base.show(io::IO, t::Term) = show_term(io, t)

isnegative(t::Real) = t < 0
function isnegative(t)
    if istree(t) && operation(t) === (*)
        coeff = first(arguments(t))
        return isnegative(coeff)
    end
    return false
end

setargs(t, args) = Term{symtype(t)}(operation(t), args)
cdrargs(args) = setargs(t, cdr(args))

print_arg(io, x::Union{Complex, Rational}; paren=true) = print(io, "(", x, ")")
isbinop(f) = istree(f) && !istree(operation(f)) && Base.isbinaryoperator(nameof(operation(f)))
function print_arg(io, x; paren=false)
    if paren && isbinop(x)
        print(io, "(", x, ")")
    else
        print(io, x)
    end
end
print_arg(io, s::String; paren=true) = show(io, s)
function print_arg(io, f, x)
    f !== (*) && return print_arg(io, x)
    if Base.isbinaryoperator(nameof(f))
        print_arg(io, x, paren=true)
    else
        print_arg(io, x)
    end
end

function remove_minus(t)
    !istree(t) && return -t
    @assert operation(t) == (*)
    args = arguments(t)
    @assert args[1] < 0
    [-args[1], args[2:end]...]
end

function show_add(io, args)
    negs = filter(isnegative, args)
    nnegs = filter(!isnegative, args)
    for (i, t) in enumerate(nnegs)
        i != 1 && print(io, " + ")
        print_arg(io, +,  t)
    end

    for (i, t) in enumerate(negs)
        if i==1 && isempty(nnegs)
            print_arg(io, -, t)
        else
            print(io, " - ")
            show_mul(io, remove_minus(t))
        end
    end
end

function show_pow(io, args)
    base, ex = args

    if base isa Real && base < 0
        print(io, "(")
        print_arg(io, base)
        print(io, ")")
    else
        print_arg(io, base, paren=true)
    end
    print(io, "^")
    print_arg(io, ex, paren=true)
end

function show_mul(io, args)
    length(args) == 1 && return print_arg(io, *, args[1])

    minus = args[1] isa Number && args[1] == -1
    unit = args[1] isa Number && args[1] == 1

    paren_scalar = (args[1] isa Complex && !_iszero(imag(args[1]))) ||
                   args[1] isa Rational ||
                   (args[1] isa Number && !isfinite(args[1]))

    nostar = minus || unit ||
            (!paren_scalar && args[1] isa Number && !(args[2] isa Number))

    for (i, t) in enumerate(args)
        if i != 1
            if i==2 && nostar
            else
                print(io, "*")
            end
        end
        if i == 1 && minus
            print(io, "-")
        elseif i == 1 && unit
        else
            print_arg(io, *, t)
        end
    end
end

function show_ref(io, f, args)
    x = args[1]
    idx = args[2:end]

    istree(x) && print(io, "(")
    print(io, x)
    istree(x) && print(io, ")")
    print(io, "[")
    for i=1:length(idx)
        print_arg(io, idx[i])
        i != length(idx) && print(io, ", ")
    end
    print(io, "]")
end

function show_call(io, f, args)
    fname = istree(f) ? Symbol(repr(f)) : nameof(f)
    binary = Base.isbinaryoperator(fname)
    if binary
        for (i, t) in enumerate(args)
            i != 1 && print(io, " $fname ")
            print_arg(io, t, paren=true)
        end
    else
        if f isa Sym
            Base.show_unquoted(io, nameof(f))
        else
            Base.show(io, f)
        end
        print(io, "(")
        for i=1:length(args)
            print(io, args[i])
            i != length(args) && print(io, ", ")
        end
        print(io, ")")
    end
end

function show_term(io::IO, t)
    if get(io, :simplify, show_simplified[])
        return print(IOContext(io, :simplify=>false), simplify(t))
    end

    f = operation(t)
    args = arguments(t)

    if f === (+)
        show_add(io, args)
    elseif f === (*)
        show_mul(io, args)
    elseif f === (^)
        show_pow(io, args)
    elseif f === (getindex)
        show_ref(io, f, args)
    else
        show_call(io, f, args)
    end

    return nothing
end

showraw(io, t) = Base.show(IOContext(io, :simplify=>false), t)
showraw(t) = showraw(stdout, t)

#=
function Base.show(io::IO, f::Symbolic{<:FnType{X,Y}}) where {X,Y}
    print(io, nameof(f))
    # Use `Base.unwrap_unionall` to handle `Tuple{T} where T`. This is not the
    # best printing, but it's better than erroring.
    argrepr = join(map(t->"::"*string(t), Base.unwrap_unionall(X).parameters), ", ")
    print(io, "(", argrepr, ")")
    print(io, "::", Y)
end
=#

function Base.show(io::IO, v::BasicSymbolic)
    if exprtype(v) === SYM
        Base.show_unquoted(io, v.name)
    else
        show_term(io, v)
    end
end

###
### Symbolic function / type inference
###

"""
    promote_symtype(f, Ts...)

The result of applying `f` to arguments of [`symtype`](#symtype) `Ts...`

```julia
julia> promote_symtype(+, Real, Real)
Real

julia> promote_symtype(+, Complex, Real)
Number

julia> @syms f(x)::Complex
(f(::Number)::Complex,)

julia> promote_symtype(f, Number)
Complex
```

When constructing [`Term`](#Term)s without an explicit symtype,
`promote_symtype` is used to figure out the symtype of the Term.
"""
promote_symtype(f, Ts...) = Any

#---------------------------
#---------------------------
#### Function-like variables
#---------------------------

# Maybe don't even need a new type, can just use Sym{FnType}
struct FnType{X<:Tuple,Y} end

function (f::Symbolic)(args...)
    if isterm(f) && f.f isa FnType
        Term{promote_symtype(f.f, symtype.(args)...)}(f, Any[args...])
    else
        error("Sym $f is not callable. " *
              "Use @syms $f(var1, var2,...) to create it as a callable.")
    end
end

"""
    promote_symtype(f::Sym{FnType{X,Y}}, arg_symtypes...)

The output symtype of applying variable `f` to arugments of symtype `arg_symtypes...`.
if the arguments are of the wrong type then this function will error.
"""
function promote_symtype(f::FnType{X,Y}, args...) where {X, Y}
    if X === Tuple
        return Y
    end

    # This is to handle `Tuple{T} where T`, so we cannot reliably query the type
    # parameters of the `Tuple` in `FnType`.
    t = Tuple{args...}
    if !(t <: X)
        error("$t is not a subtype of $X.")
    end
    return Y
end

@inline isassociative(op) = op === (+) || op === (*)

_promote_symtype(f::Sym, args) = promote_symtype(f, map(symtype, args)...)
function _promote_symtype(f, args)
    return Real
    if length(args) == 0
        promote_symtype(f)
    elseif length(args) == 1
        if f in monadic
            valtype2type(min(REAL, valtype(args[1])))
        else
            promote_symtype(f, symtype(args[1]))
        end
    elseif length(args) == 2
        promote_symtype(f, symtype(args[1]), symtype(args[2]))
    elseif isassociative(f)
        mapfoldl(symtype, (x,y) -> promote_symtype(f, x, y), args)
    else
        promote_symtype(f, map(symtype, args)...)
    end
end

###
### Macro
###

"""
    @syms <lhs_expr>[::T1] <lhs_expr>[::T2]...

For instance:

    @syms foo::Real bar baz(x, y::Real)::Complex

Create one or more variables. `<lhs_expr>` can be just a symbol in which case
it will be the name of the variable, or a function call in which case a function-like
variable which has the same name as the function being called. The Sym type, or
in the case of a function-like Sym, the output type of calling the function
can be set using the `::T` syntax.

# Examples:

- `@syms foo bar::Real baz::Int` will create
variable `foo` of symtype `Number` (the default), `bar` of symtype `Real`
and `baz` of symtype `Int`
- `@syms f(x) g(y::Real, x)::Int h(a::Int, f(b))` creates 1-arg `f` 2-arg `g`
and 2 arg `h`. The second argument to `h` must be a one argument function-like
variable. So, `h(1, g)` will fail and `h(1, f)` will work.
"""
macro syms(xs...)
    defs = map(xs) do x
        n, t = _name_type(x)
        :($(esc(n)) = Sym{$(esc(t))}($(Expr(:quote, n))))
        nt = _name_type(x)
        n, t = nt.name, nt.type
        :($(esc(n)) = Sym{$(esc(t))}($(Expr(:quote, n))))
    end
    Expr(:block, defs...,
         :(tuple($(map(x->esc(_name_type(x).name), xs)...))))
end

function syms_syntax_error()
    error("Incorrect @syms syntax. Try `@syms x::Real y::Complex g(a) f(::Real)::Real` for instance.")
end

function _name_type(x)
    if x isa Symbol
        return (name=x, type=Real)
    elseif x isa Expr && x.head === :(::)
        if length(x.args) == 1
            return (name=nothing, type=x.args[1])
        end
        lhs, rhs = x.args[1:2]
        if lhs isa Expr && lhs.head === :call
            # e.g. f(::Real)::Unreal
            type = map(x->_name_type(x).type, lhs.args[2:end])
            return (name=lhs.args[1], type=:($FnType{Tuple{$(type...)}, $rhs}))
        else
            return (name=lhs, type=rhs)
        end
    elseif x isa Expr && x.head === :ref
        ntype = _name_type(x.args[1]) # a::Number
        N = length(x.args)-1
        return (name=ntype.name,
                type=:(Array{$(ntype.type), $N}),
                array_metadata=:(Base.Slice.(($(x.args[2:end]...),))))
    elseif x isa Expr && x.head === :call
        return _name_type(:($x::Real))
    else
        syms_syntax_error()
    end
end

###
### Arithmetic
###
_merge(f, d, others...; filter=x->false) = _merge!(f, Dict{Any,Any}(d), others...; filter=filter)
function _merge!(f, d, others...; filter=x->false)
    acc = d
    for other in others
        for (k, v) in other
            v = f(v)
            if haskey(acc, k)
                v = acc[k] + v
            end
            if filter(v)
                delete!(acc, k)
            else
                acc[k] = v
            end
        end
    end
    acc
end

function mapvalues(f, d1::AbstractDict)
    d = copy(d1)
    for (k, v) in d
        d[k] = f(k, v)
    end
    d
end

#add_t(a,b) = promote_symtype(+, symtype(a), symtype(b))
#sub_t(a,b) = promote_symtype(-, symtype(a), symtype(b))
#sub_t(a) = promote_symtype(-, symtype(a))
# TODO
add_t(a,b) = REAL
sub_t(a,b) = REAL
sub_t(a) = REAL

import Base: (+), (-), (*), (//), (/), (\), (^)
function +(a::BasicSymbolic, b::BasicSymbolic)
    if isadd(a) && isadd(b)
        return Add(add_t(a,b),
            a.coeff + b.coeff,
            _merge(+, a.dict, b.dict, filter=_iszero))
    elseif isadd(a)
        coeff, dict = makeadd(1, 0, b)
        return Add(add_t(a,b), a.coeff + coeff, _merge(+, a.dict, dict, filter=_iszero))
    elseif isadd(b)
        return b + a
    end
    Add(add_t(a,b), makeadd(1, 0, a, b)...)
end

function +(a::Number, b::BasicSymbolic)
    iszero(a) && return b
    if isadd(b)
        Add(add_t(a,b), a + b.coeff, b.dict)
    else
        Add(add_t(a,b), makeadd(1, a, b)...)
    end
end

+(a::BasicSymbolic, b::Number) = b + a

+(a::BasicSymbolic) = a

function -(a::BasicSymbolic)
    isadd(a) ? Add(sub_t(a), -a.coeff, mapvalues((_,v) -> -v, a.dict)) :
    Add(sub_t(a), makeadd(-1, 0, a)...)
end

function -(a::BasicSymbolic, b::BasicSymbolic)
    isadd(a) && isadd(b) ? Add(sub_t(a,b),
                               a.coeff - b.coeff,
                               _merge(-, a.dict,
                                      b.dict,
                                      filter=_iszero)) : a + (-b)
end

-(a::Number, b::BasicSymbolic) = a + (-b)
-(a::BasicSymbolic, b::Number) = a + (-b)


#mul_t(a,b) = promote_symtype(*, symtype(a), symtype(b))
#mul_t(a) = promote_symtype(*, symtype(a))
mul_t(a,b) = REAL
mul_t(a) = REAL

*(a::BasicSymbolic) = a

function *(a::BasicSymbolic, b::BasicSymbolic)
    # Always make sure Div wraps Mul
    if isdiv(a) && isdiv(b)
        Div(a.num * b.num, a.den * b.den)
    elseif isdiv(a)
        Div(a.num * b, a.den)
    elseif isdiv(b)
        Div(a * b.num, b.den)
    elseif ismul(a) && ismul(b)
        Mul(mul_t(a, b),
            a.coeff * b.coeff,
            _merge(+, a.dict, b.dict, filter=_iszero))
    elseif ismul(a) && ispow(b)
        if b.exp isa Number
            Mul(mul_t(a, b),
                a.coeff, _merge(+, a.dict, Base.ImmutableDict(b.base=>b.exp), filter=_iszero))
        else
            Mul(mul_t(a, b),
                a.coeff, _merge(+, a.dict, Base.ImmutableDict(b=>1), filter=_iszero))
        end
    elseif ispow(a) && ismul(b)
        b * a
    else
        Mul(mul_t(a,b), makemul(1, a, b)...)
    end
end

function *(a::Number, b::BasicSymbolic)
    if iszero(a)
        a
    elseif isone(a)
        b
    elseif isdiv(b)
        Div(a*b.num, b.den)
    elseif isadd(b)
        # 2(a+b) -> 2a + 2b
        T = promote_symtype(+, typeof(a), symtype(b))
        Add(T, b.coeff * a, Dict{Any,Any}(k=>v*a for (k, v) in b.dict))
    else
        Mul(mul_t(a, b), makemul(a, b)...)
    end
end

*(a::BasicSymbolic, b::Number) = b * a

\(a::BasicSymbolic, b::Union{Number, BasicSymbolic}) = b / a

\(a::Number, b::BasicSymbolic) = b / a

/(a::BasicSymbolic, b::Number) = (b isa Integer ? 1//b : inv(b)) * a

//(a::Union{BasicSymbolic, Number}, b::BasicSymbolic) = a / b

//(a::BasicSymbolic, b::T) where {T <: Number} = (one(T) // b) * a

const Rat = Union{Rational, Integer}

function ratcoeff(x)
    if ismul(x)
        ratcoeff(x.coeff)
    elseif x isa Rat
        true, x
    else
        false, NaN
    end
end
ratio(x::Integer,y::Integer) = iszero(rem(x,y)) ? div(x,y) : x//y
ratio(x::Rat,y::Rat) = x//y
function maybe_intcoeff(x)
    if ismul(x)
        x.coeff isa Rational && isone(x.coeff.den) ? Setfield.@set!(x.coeff = x.coeff.num) : x
    elseif x isa Rational
        isone(x.den) ? x.num : x
    else
        x
    end
end

/(a::Union{BasicSymbolic,Number}, b::BasicSymbolic) = Div(a,b)

function ^(a::BasicSymbolic, b)
    if ismul(a) && b isa Number
        coeff = unstable_pow(a.coeff, b)
        Mul(promote_symtype(^, symtype(a), symtype(b)),
            coeff, mapvalues((k, v) -> b*v, a.dict))
    else
        Pow(a, b)
    end
end

^(a::BasicSymbolic, b::BasicSymbolic) = Pow(a, b)

^(a::Number, b::BasicSymbolic) = Pow(a, b)

include("utils.jl")
include("methods.jl")
