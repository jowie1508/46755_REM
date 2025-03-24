########################
# This script contains the code for Step 6: Reserve Market
# In the first part, the initial data is loaded and some market settings printed out.
# The second part contains the optimization problem of the reserve market.
# The third part is the optimization problem of the day ahead market, taking into account the effect/allocation of 
# generation capacity in the reserve market
########################
# Imports
########################

using JuMP
using Plots
using Printf
using Gurobi

include("plot_demand_supply.jl")

########################
# Functions
########################

function stepwise_curve(quantity, price)
    n = length(quantity)

    # Include (0, first_price) as starting point
    step_q = vcat(0, repeat(quantity, inner=2))  # Repeat each quantity twice
    step_p = vcat(repeat(price, inner=2))        # Repeat each price twice

    return step_q[1:end-1], step_p  # Remove the last duplicate to avoid an extra step
end

########################
# Initial Setup
########################

#define bid price for demand in euro/MWh (taken from NordPool data 11/02 13:00-14:00) for 17 loads
Bid_Price = [28; 26.4; 24.3; 22; 19.7; 18; 17.2; 17; 16.8; 15.4; 14.9; 14.1; 13.7; 13; 12.8; 12.4; 5]

#number of demand loads
D = length(Bid_Price)

#Offer price for generators in euro/MWh (taken from paper Ci (transformed in EUR) and including also price for windpower)
Offer_Price = [12.3; 12.3; 19; 19; 24; 9.7; 9.7; 5.5; 5; 0; 9.7; 10; 0; 0; 0; 0; 0; 0]

#number of generators
G = length(Offer_Price)

#Maximum power output of generator unit g in MWh, capacity ((taken from paper data Pimax))
Pgmax = [152; 152; 350; 591; 60; 155; 155; 400; 400; 300; 310; 350; 150; 120; 140; 100; 130; 110]

#Maximum load of demand d in MWh (taken from paper data system demand*% system load)
Pdmax = [96; 86; 159; 65; 63; 121; 111; 151; 154; 171; 234; 171; 279; 88; 295; 161; 113]

# List of flexible generators (participating in the reserve market)
flexible_generators = [1, 2, 3, 4, 5, 8, 9, 12]
total_flex_capacity = sum(Pgmax[g] for g in flexible_generators)  # Total available flexible generation

# Total required reserves
total_demand = sum(Pdmax)  # Sum of all demand
required_upward_reserve = 0.15 * total_demand  # 15% of total demand
required_downward_reserve = 0.10 * total_demand  # 10% of total demand


println("\n=========================================")
println(" INITIAL SETUP ")
println("=========================================\n")

# Display Bid Prices for Demand
println("Demand Bid Prices (€/MWh):")
println("──────────────────────────────")
for d in 1:length(Bid_Price)
    @printf("Load %2d: %6.2f €/MWh\n", d, Bid_Price[d])
end
println("\nTotal Demand Loads: ", D, "\n")

# Display Offer Prices for Generators
println("Generator Offer Prices (€/MWh):")
println("───────────────────────────────────")
for g in 1:length(Offer_Price)
    @printf("Generator %2d: %6.2f €/MWh\n", g, Offer_Price[g])
end
println("\nTotal Generators: ", G, "\n")

# Display Maximum Power Output per Generator
println("Generator Maximum Capacities (MW):")
println("──────────────────────────────────────")
for g in 1:length(Pgmax)
    @printf("Generator %2d: %6.1f MW\n", g, Pgmax[g])
end
println()

# Display Maximum Load per Demand
println("Maximum Load per Demand (MW):")
println("──────────────────────────────────")
for d in 1:length(Pdmax)
    @printf("Load %2d: %6.1f MW\n", d, Pdmax[d])
end
println()

# Display Flexible Generators
println("Flexible Generators Participating in the Reserve Market:")
println("──────────────────────────────────────────────────────────")
println("Generators:", flexible_generators)
println("Total Flexible Generator Capacity: %.1f MW", total_flex_capacity)

# Display Total Demand and Reserves
println("\nMarket-Wide Statistics:")
println("──────────────────────────")
@printf("Total System Demand: %.1f MW\n", sum(Pdmax))
@printf("Required Upward Reserve (15%%): %.1f MW\n", required_upward_reserve)
@printf("Required Downward Reserve (10%%): %.1f MW\n", required_downward_reserve)

println("\n=========================================")


########################
# Clear Reserve Market
########################

println("\n=========================================")
println(" RESERVE MARKET CLEARING ")
println("=========================================\n")

m_reserve = Model(Gurobi.Optimizer)

@variable(m_reserve, 0 <= R_up[g in flexible_generators] <= Pgmax[g])  # Upward Reserve
@variable(m_reserve, 0 <= R_down[g in flexible_generators] <= Pgmax[g])  # Downward Reserve

# Objective: Minimize total reserve procurement cost
@objective(m_reserve, Min, sum(Offer_Price[g] * (R_up[g] + R_down[g]) for g in flexible_generators))

# Constraint: Ensure required reserve procurement
reserve_up = @constraint(m_reserve, sum(R_up[g] for g in flexible_generators) == 0.15 * sum(Pdmax))
reserve_down = @constraint(m_reserve, sum(R_down[g] for g in flexible_generators) == 0.10 * sum(Pdmax))

# Constraint: Limit Upward and Downward Reserve to max 50% of installed capacity
up_price = @constraint(m_reserve, [g in flexible_generators], R_up[g] <= 0.5 * Pgmax[g])  # Upward ≤ 50% of installed capacity
down_price = @constraint(m_reserve, [g in flexible_generators], R_down[g] <= 0.5 * Pgmax[g])  # Downward ≤ 50% of installed capacity

# Solve the Reserve Market
optimize!(m_reserve)

# Extract dual variables
λ_up = dual(reserve_up)
λ_down = dual(reserve_down)

# Extract Optimized Reserve Values
R_up_values = Dict(g => value(R_up[g]) for g in flexible_generators)
R_down_values = Dict(g => value(R_down[g]) for g in flexible_generators)
Reserve_values = Dict(g => R_up_values[g] + R_down_values[g] for g in flexible_generators)


# Print the results
println("\nObjective Value Reserve: ", objective_value(m_reserve))
println("\n Reserve Market Clearing Prices:")
println("   • Upward Reserve Price: ", λ_up, " €/MWh")
println("   • Downward Reserve Price: ", λ_down, " €/MWh")
println("\n Reserve Market Results:")
println("   • Total Upward Reserve Procured: ", sum(R_up_values[g] for g in flexible_generators), " MW")
println("   • Total Downward Reserve Procured: ", sum(R_down_values[g] for g in flexible_generators), " MW")
println("\n Flexible Generators' Committed Reserves:")
for g in flexible_generators
    println("   • Generator $g: Upward = $(round(R_up_values[g], digits=2)) MW, Downward = $(round(R_down_values[g], digits=2)) MW")
end
println("\n")

########################
# Plot adapted supply demand curve
########################

num_generators = length(Pgmax)  # Ensure the total number of generators
R_up_list = [get(R_up_values, g, 0.0) for g in 1:num_generators]
Pgmax_adjusted = [Pgmax[g] - R_up_list[g] for g in 1:num_generators]

# Display the results
println("Generator | Original Pgmax (MW) | Adjusted Pgmax (MW)")
println("------------------------------------------------------")
for g in 1:num_generators
    println("    $g     |      $(Pgmax[g]) MW       |      $(Pgmax_adjusted[g]) MW")
end


plot_curve_with_reserve(Offer_Price, Pgmax, Pgmax_adjusted, Bid_Price, Pdmax)

########################
# Clear Day Ahead market
########################

println("\n=========================================")
println(" DAY AHEAD MARKET CLEARING ")
println("=========================================\n")


## Create a model
m = Model(Gurobi.Optimizer)

#Define the variables
@variable(m, 0 <= Pd[1:D]) #Power demand in MWh
@variable(m, 0 <= Pg[1:G]) #Power generation in MWh

#Define the objective function
@objective(m, Max, sum(Bid_Price[d] * Pd[d] for d in 1:D) - sum(Offer_Price[g] * Pg[g] for g in 1:G))

#Define the constraints
# Max generation capacity constraint
@constraint(m, [g = 1:G], Pg[g] <= Pgmax[g])
# Max demand constraint
@constraint(m, [d = 1:D], Pd[d] <= Pdmax[d])
# Balance constraint
@constraint(m, balance, sum(Pg[g] for g in 1:G) - sum(Pd[d] for d in 1:D) == 0)
# Adjust generation constraints for flexible generators
@constraint(m, [g in flexible_generators], Pg[g] <= Pgmax[g] - R_up_values[g])  
@constraint(m, [g in flexible_generators], Pg[g] >= R_down_values[g])           

#Solve the model
optimize!(m)

println("\n=========================================\n")


println("\nChecking Day-Ahead Market Constraints:")
for g in flexible_generators
    println("Generator $g: Pg[g] = $(round(value(Pg[g]), digits=2)) MW, Limit: [$(round(R_down_values[g], digits=2)), $(round(Pgmax[g] - R_up_values[g], digits=2))] MW")
end


# Display results
println("\nTotal Maximum Demand: ", sum(Pdmax))
println("\nTotal Maximum Generation: ", sum(Pgmax))
println("\nMarket Clearing Price: ", dual(balance))  # Shadow price (λ) gives market-clearing price
println("\nTotal Social Welfare: ", objective_value(m))

println("\n=========================================\n")


