# PREAMBLE

# PKG_SETUP

# ## Setup

using LinearAlgebra
using Plots
using DirectTrajectoryOptimization 

# ## horizon 
T = 101 

# ## acrobot 
num_state = 4 
num_action = 1 
num_parameter = 0 

function acrobot(x, u, w)
    mass1 = 1.0  
    inertia1 = 0.33  
    length1 = 1.0 
    lengthcom1 = 0.5 

    mass2 = 1.0  
    inertia2 = 0.33  
    length2 = 1.0 
    lengthcom2 = 0.5 

    gravity = 9.81 
    friction1 = 0.1 
    friction2 = 0.1

    function M(x, w)
        a = (inertia1 + inertia2 + mass2 * length1 * length1
            + 2.0 * mass2 * length1 * lengthcom2 * cos(x[2]))

        b = inertia2 + mass2 * length1 * lengthcom2 * cos(x[2])

        c = inertia2

       return [a b; b c]
    end

    function Minv(x, w)
        a = (inertia1 + inertia2 + mass2 * length1 * length1
            + 2.0 * mass2 * length1 * lengthcom2 * cos(x[2]))

        b = inertia2 + mass2 * length1 * lengthcom2 * cos(x[2])

        c = inertia2

        return 1.0 / (a * c - b * b) * [c -b; -b a]
    end

    function τ(x, w)
        a = (-1.0 * mass1 * gravity * lengthcom1 * sin(x[1])
            - mass2 * gravity * (length1 * sin(x[1])
            + lengthcom2 * sin(x[1] + x[2])))

        b = -1.0 * mass2 * gravity * lengthcom2 * sin(x[1] + x[2])

        return [a; b]
    end

    function C(x, w)
        a = -2.0 * mass2 * length1 * lengthcom2 * sin(x[2]) * x[4]
        b = -1.0 * mass2 * length1 * lengthcom2 * sin(x[2]) * x[4]
        c = mass2 * length1 * lengthcom2 * sin(x[2]) * x[3]
        d = 0.0

        return [a b; c d]
    end

    function B(x, w)
        [0.0; 1.0]
    end

    q = view(x, 1:2)
    v = view(x, 3:4)

    qdd = Minv(q, w) * (-1.0 * C(x, w) * v
            + τ(q, w) + B(q, w) * u[1] - [friction1; friction2] .* v)

    return [x[3]; x[4]; qdd[1]; qdd[2]]
end

function midpoint_implicit(y, x, u, w)
    h = 0.05 # timestep 
    y - (x + h * acrobot(0.5 * (x + y), u, w))
end

# ## model
dt = Dynamics(midpoint_implicit, num_state, num_state, num_action, num_parameter=num_parameter)
dynamics = [dt for t = 1:T-1] 

# ## initialization
x1 = [0.0; 0.0; 0.0; 0.0] 
xT = [0.0; π; 0.0; 0.0] 

# ## objective 
ot = (x, u, w) -> 0.1 * dot(x[3:4], x[3:4]) + 0.1 * dot(u, u)
oT = (x, u, w) -> 0.1 * dot(x[3:4], x[3:4])
ct = Cost(ot, num_state, num_action, num_parameter=num_parameter)
cT = Cost(oT, num_state, 0, num_parameter=num_parameter)
objective = [[ct for t = 1:T-1]..., cT]

# ## constraints
bnd1 = Bound(num_state, num_action)
bndt = Bound(num_state, num_action)
bndT = Bound(num_state, 0)
bounds = [bnd1, [bndt for t = 2:T-1]..., bndT]

constraints = [
        Constraint((x, u, w) -> x - x1, num_state, num_action), 
        [Constraint() for t = 2:T-1]..., 
        Constraint((x, u, w) -> x - xT, num_state, 0)
       ]


# ## problem 
solver = Solver(dynamics, objective, constraints, bounds, 
    options=Options{Float64}())

# ## initialize
x_interpolation = linear_interpolation(x1, xT, T)
u_guess = [1.0 * randn(num_action) for t = 1:T-1]

initialize_states!(solver, x_interpolation)
initialize_controls!(solver, u_guess)

# ## solve
@time solve!(solver)

# ## solution
x_sol, u_sol = get_trajectory(solver)

@show x_sol[1]
@show x_sol[T]

# ## state
plot(hcat(x_sol...)')

# ## control
plot(hcat(u_sol[1:end-1]..., u_sol[end-1])', linetype = :steppost)