using JuMP
import Pkg
include("plot_demand_supply.jl")

Pkg.add("Gurobi")
using Gurobi
using Printf  # For formatted printing

############################
# Utility Functions
############################

"""
    stepwise_curve(quantity::Vector, price::Vector) -> (Vector, Vector)

Constructs a stepwise curve from quantity and price vectors by repeating each point to 
form horizontal steps, commonly used for supply/demand visualization.

# Arguments
- `quantity`: Vector of quantity levels (e.g., power in MWh)
- `price`: Corresponding vector of prices (e.g., €/MWh)

# Returns
- A tuple of vectors representing the x and y coordinates of the stepwise curve.
"""
function stepwise_curve(quantity, price)
    n = length(quantity)
    step_q = vcat(0, repeat(quantity, inner=2))  # Repeat each quantity twice
    step_p = vcat(repeat(price, inner=2))        # Repeat each price twice
    return step_q[1:end-1], step_p
end

############################
# Market Data Input
############################

Bid_Price = [28; 26.4; 24.3; 22; 19.7; 18; 17.2; 17; 16.8; 15.4; 14.9; 14.1; 13.7; 13; 12.8; 12.4; 11.2]
D = length(Bid_Price)

Offer_Price = [12.3; 12.3; 19; 19; 24; 9.7; 9.7; 5.5; 5; 0; 9.7; 10; 0; 0; 0; 0; 0; 0]
G = length(Offer_Price)

Pgmax = [152; 152; 350; 591; 60; 155; 155; 400; 400; 300; 310; 350; 150; 120; 140; 100; 130; 110]
Pdmax = [96; 86; 159; 65; 63; 121; 111; 151; 154; 171; 234; 171; 279; 88; 295; 161; 113]

plot_curve(Offer_Price, Pgmax, Bid_Price, Pdmax)

############################
# Model Definition
############################

m = Model(Gurobi.Optimizer)

@variable(m, 0 <= Pd[1:D])
@variable(m, 0 <= Pg[1:G])

@objective(m, Max, sum(Bid_Price[d] * Pd[d] for d in 1:D) - sum(Offer_Price[g] * Pg[g] for g in 1:G))

@constraint(m, [g = 1:G], Pg[g] <= Pgmax[g])
@constraint(m, [d = 1:D], Pd[d] <= Pdmax[d])
@constraint(m, balance, sum(Pd[d] for d in 1:D) - sum(Pg[g] for g in 1:G) == 0)

optimize!(m)

############################
# Results & Outputs
############################

if termination_status(m) == MOI.OPTIMAL
    Pg_values = value.(Pg)
    Pd_values = value.(Pd)
    active_generators = findall(x -> x > 0, Pg_values)
    lambda_estimated = maximum(Offer_Price[active_generators])
    @printf("Estimated Market Clearing Price: €%.2f\n", lambda_estimated)
else
    println("Optimization did not converge!")
end

@printf("Total Social Welfare: €%.2f\n", objective_value(m))

# Generator profits
sorted_indices_offer = sortperm(Offer_Price)
Offer_Price_sorted = Offer_Price[sorted_indices_offer]
Pg_values_sorted = Pg_values[sorted_indices_offer]

profit = [(lambda_estimated - Offer_Price_sorted[g]) * Pg_values_sorted[g] for g in 1:G]
profit_rounded = round.(profit, digits=2)
println("Profit for each generator: ", profit_rounded)

# Demand utility
sorted_indices_bid = sortperm(Bid_Price, rev=true)
Bid_Price_sorted = Bid_Price[sorted_indices_bid]
Pd_values_sorted = Pd_values[sorted_indices_bid]

utility = [Pd_values_sorted[d] * (Bid_Price_sorted[d] - lambda_estimated) for d in 1:D]
utility_rounded = round.(utility, digits=2)
println("Utility for each demand: ", utility_rounded)
