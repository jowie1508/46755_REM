# =============================================================================
# Task: U.S.-Style Joint Energy + Reserve Market Clearing
# -----------------------------------------------------------------------------
# Use:
#     Simulates a one-period electricity market with joint clearing of 
#     energy and reserves, similar to U.S.-style ISO/RTO operations.
#
# Type:
#     Linear optimization model using JuMP and Gurobi
#
# Inputs:
#     - Generator offer prices and capacity limits
#     - Demand bid prices and max demand
#     - Reserve requirements (up/down)
#     - Set of flexible generators
#
# Function:
#     Simultaneously solves for:
#         • Energy dispatch
#         • Reserve allocations (up/down)
#         • Market-clearing prices
#         • Generator limits considering reserve
#
# Output:
#     - Generator dispatch and reserve
#     - Market-clearing price (energy)
#     - Total social welfare
#     - Optional adjusted supply/demand curve
# =============================================================================

using JuMP
using Gurobi
using Printf
using Plots

include("plot_demand_supply.jl")  # Custom plotting function

# ----------------------------- Input Data ----------------------------------- #

Bid_Price = [28; 26.4; 24.3; 22; 19.7; 18; 17.2; 17; 16.8; 15.4; 14.9; 14.1; 13.7; 13; 12.8; 12.4; 5]
Offer_Price = [12.3; 12.3; 19; 19; 24; 9.7; 9.7; 5.5; 5; 0; 9.7; 10; 0; 0; 0; 0; 0; 0]

Pgmax = [152; 152; 350; 591; 60; 155; 155; 400; 400; 300; 310; 350; 150; 120; 140; 100; 130; 110]
Pdmax = [96; 86; 159; 65; 63; 121; 111; 151; 154; 171; 234; 171; 279; 88; 295; 161; 113]

flexible_generators = [1, 2, 3, 4, 5, 8, 9, 12]

D = length(Bid_Price)
G = length(Offer_Price)

total_demand = sum(Pdmax)
required_upward_reserve = 0.15 * total_demand
required_downward_reserve = 0.10 * total_demand

# ----------------------------- Model Setup ---------------------------------- #

println("\n=========================================")
println(" U.S.-STYLE JOINT ENERGY + RESERVE MARKET ")
println("=========================================\n")

model = Model(Gurobi.Optimizer)

# Decision variables
@variable(model, 0 <= Pd[d=1:D] <= Pdmax[d])      # Demand served
@variable(model, 0 <= Pg[g=1:G] <= Pgmax[g])      # Generator output
@variable(model, 0 <= R_up[g in flexible_generators])    # Upward reserve
@variable(model, 0 <= R_down[g in flexible_generators])  # Downward reserve

# Objective: Maximize social welfare = consumer benefit - generation & reserve costs
@objective(model, Max,
    sum(Bid_Price[d] * Pd[d] for d in 1:D)
  - sum(Offer_Price[g] * Pg[g] for g in 1:G)
  - sum(Offer_Price[g] * (R_up[g] + R_down[g]) for g in flexible_generators)
)

# Generator reserve feasibility constraints
@constraint(model, [g in flexible_generators], Pg[g] + R_up[g] <= Pgmax[g])   # Don't exceed total capacity
@constraint(model, [g in flexible_generators], Pg[g] - R_down[g] >= 0)        # Keep minimum output non-negative

# Reserve requirements
@constraint(model, sum(R_up[g] for g in flexible_generators) == required_upward_reserve)
@constraint(model, sum(R_down[g] for g in flexible_generators) == required_downward_reserve)

# Power balance constraint
@constraint(model, balance, sum(Pg[g] for g in 1:G) == sum(Pd[d] for d in 1:D))

# Constraint: Limit Upward and Downward Reserve to max 50% of installed capacity
up_price = @constraint(model, [g in flexible_generators], R_up[g] <= 0.5 * Pgmax[g])  # Upward ≤ 50% of installed capacity
down_price = @constraint(model, [g in flexible_generators], R_down[g] <= 0.5 * Pgmax[g])  
# ----------------------------- Solve Model ---------------------------------- #

optimize!(model)

# ----------------------------- Results -------------------------------------- #

println("\nMarket Clearing Results (U.S.-Style):")
println("────────────────────────────────────────────")

# Market-clearing price = dual of power balance constraint
@printf(" • Market Clearing Price (Energy): %.2f €/MWh\n", dual(balance))

# Reserve prices (shadow prices on reserve constraints)
#λ_up = dual(optimizer_index(model, 1))  # these can be refined if named constraints are added
#λ_down = dual(optimizer_index(model, 2))

#println(" • Upward Reserve Price:  ", round(λ_up, digits=2), " €/MWh")
#println(" • Downward Reserve Price:", round(λ_down, digits=2), " €/MWh\n")

println(" • Generator Dispatch and Reserve Allocation:")
println("Gen | Energy (MW) | R_up (MW) | R_down (MW) | Total Used (MW)")
println("-------------------------------------------------------------")
for g in 1:G
    pg = value(Pg[g])
    rup = g in flexible_generators ? value(R_up[g]) : 0.0
    rdown = g in flexible_generators ? value(R_down[g]) : 0.0
    println(@sprintf("%3d | %10.2f | %8.2f | %10.2f | %10.2f", g, pg, rup, rdown, pg + rup))
end

println("\n • Total Social Welfare: €", round(objective_value(model), digits=2))
println(" • Total Upward Reserve Procured: ", round(sum(value.(R_up)), digits=2), " MW")
println(" • Total Downward Reserve Procured: ", round(sum(value.(R_down)), digits=2), " MW")

# ------------------------- Optional Plot (Adjusted Supply) ------------------ #

Pgmax_adjusted = [
    g in flexible_generators ? Pgmax[g] - value(R_up[g]) : Pgmax[g]
    for g in 1:G
]

println("\nGenerator | Original Pgmax (MW) | Adjusted Pgmax (MW)")
println("--------------------------------------------------------")
for g in 1:G
    println("   $g     |     $(Pgmax[g])       |       $(round(Pgmax_adjusted[g], digits=1))")
end

plot_curve_with_reserve(Offer_Price, Pgmax, Pgmax_adjusted, Bid_Price, Pdmax)

println("\n=========================================\n")