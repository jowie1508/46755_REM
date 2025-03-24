"""
Power Market Clearing and Balancing Simulation

This script simulates a two-stage electricity market consisting of:

1. **Day-Ahead Market** – Clears the market by maximizing social welfare based on 
   submitted generator offers and consumer bids.
2. **Balancing Market** – Adjusts generation in response to real-time deviations, such 
   as generator outages or variable renewable output.

────────────────────────────────────────────────────────────────────────────
Main Features:
- Implements a linear optimization model using JuMP and Gurobi
- Solves the Day-Ahead Market for optimal dispatch and market clearing price
- Introduces generator-specific imbalances for the Balancing Market
- Minimizes total balancing cost using up/down regulation and curtailment
- Supports both one-price and two-price imbalance settlement schemes
- Calculates profits and utilities for each generator and consumer
- Displays key results with two-decimal formatting

────────────────────────────────────────────────────────────────────────────
Inputs:
- `Bid_Price`: Vector of consumer bid prices (€/MWh)
- `Offer_Price`: Vector of generator offer prices (€/MWh)
- `Pgmax`: Vector of generator capacities (MWh)
- `Pdmax`: Vector of consumer maximum loads (MWh)
- `G_unflex`: List of non-flexible generators not allowed to participate in balancing

────────────────────────────────────────────────────────────────────────────
Outputs:
- Market clearing price (Day-Ahead and Balancing)
- Generator dispatch and load allocation
- Profit per generator and utility per demand load
- Total social welfare and balancing cost
- Profit analysis under one-price and two-price settlement

────────────────────────────────────────────────────────────────────────────
Dependencies:
- JuMP.jl
- Gurobi.jl (licensed)
- Printf.jl
- plot_demand_supply.jl (optional visualization)

To Run:
Ensure all dependencies are installed and Gurobi is licensed. Then run the script in Julia.
"""


using JuMP
import Pkg

Pkg.add("Gurobi")

using Gurobi

############################
# Market Data Input
############################
#number of demand loads
Bid_Price = [28; 26.4; 24.3; 22; 19.7; 18; 17.2; 17; 16.8; 15.4; 14.9; 14.1; 13.7; 13; 12.8; 12.4; 5]
D = length(Bid_Price)

#Offer price for generators in euro/MWh (taken from paper Ci (transformed in EUR) and including also price for windpower)
Offer_Price = [12.3; 12.3; 19; 19; 24; 9.7; 9.7; 5.5; 5; 0; 9.7; 10; 0; 0; 0; 0; 0; 0]

G_unflex = [6; 7; 10; 11; 13; 14; 15; 16; 17; 18]  # Unflexible generators

#number of generators
G = length(Offer_Price)

#Maximum power output of generator unit g in MWh, capacity ((taken from paper data Pimax))
Pgmax = [152; 152; 350; 591; 60; 155; 155; 400; 400; 300; 310; 350; 150; 120; 140; 100; 130; 110]
#Maximum load of demand d in MWh (taken from paper data system demand*% system load)
Pdmax = [96; 86; 159; 65; 63; 121; 111; 151; 154; 171; 234; 171; 279; 88; 295; 161; 113]


#######################################
## DAY AHEAD MARKET IMPLEMENTATION   
#######################################

## Create model to solve Day-Ahead Market
m = Model(Gurobi.Optimizer)

#Define the variables
# (in first part it is NOT time dependent)
@variable(m, 0 <= Pd[1:D]) #Power demand in MWh
@variable(m, 0 <= Pg[1:G]) #Power generation in MWh

#include smt for wind power generation (?)

#Define the objective function: Maximize social welfare by subtracting the Supply area from the Offer area
@objective(m, Max, sum(Bid_Price[d] * Pd[d] for d in 1:D) - sum(Offer_Price[g] * Pg[g] for g in 1:G))

#Define the constraints
#Max generation capacity constraint - a generator cannot produce more than its maximum capacity and min 0
@constraint(m, [g = 1:G], Pg[g] <= Pgmax[g])

#Max demand constraint - a load can max consume its maximum capacity and min 0
@constraint(m, [d = 1:D], Pd[d] <= Pdmax[d])


#Balance constraint - total demand has to equal total supply
@constraint(m, balance, sum(Pd[d] for d in 1:D) - sum(Pg[g] for g in 1:G) == 0)

#Solve the model
optimize!(m)


if termination_status(m) == MOI.OPTIMAL
    Pg_values = value.(Pg)  # Get generator outputs
    Pd_values = value.(Pd) # Get demand loads
    active_generators = findall(x -> x > 0, Pg_values)  # Generators producing power

    # Find the marginal generator (last generator needed to meet demand)
    lambda_estimated = maximum(Offer_Price[active_generators])  # Estimate λ

    println("Estimated Market Clearing Price: ", lambda_estimated)
else
    println("Optimization did not converge!")
end


# Display results
println("_________________Results for Day-Ahead Market:_________________")
#println("Total Maximum Demand: ", sum(Pdmax))
#println("Total Maximum Generation: ", sum(Pgmax))
println("Market Clearing Price: ", dual(balance))  # Shadow price (λ) gives market-clearing price
#println("Optimal Demand Allocation: ", value.(Pd))
println("Optimal Generation Dispatch: ", value.(Pg))
println("Total Social Welfare: ", objective_value(m))

# Get the permutation indices to sort offer and Bid prices
sorted_indices_offer = sortperm(Offer_Price)
sorted_indices_bid = sortperm(Bid_Price, rev=true)

# Sort Prices and Pg/Pd values using the permutation indices
Offer_Price_sorted = Offer_Price[sorted_indices_offer]
Pg_values_sorted = Pg_values[sorted_indices_offer]
Bid_Price_sorted = Bid_Price[sorted_indices_bid]
Pd_values_sorted = Pd_values[sorted_indices_bid]

# Calculate profit for each generator and utility for each demand
profit_DA_sorted = [(lambda_estimated - Offer_Price_sorted[g]) * Pg_values_sorted[g] for g in 1:G]
#println("Profit for each generator:", profit_DA_sorted)
utility_DA_sorted = [Pd_values_sorted[d] * (Bid_Price_sorted[d] - lambda_estimated) for d in 1:D]
#println("Utility for each demand:", utility_DA_sorted)


#######################################
## BALANCING MARKET IMPLEMENTATION   ##
#######################################

## Create new market condition for Balancing Marktet
Pgreal = Float64.(Pgmax)  # Convert to Float64

# 1) Retrieve the Day-Ahead results and adapt to balancing conditions:
p_DA = lambda_estimated         # or dual(balance) from the Day-Ahead model
Pg_DA = Pg_values               # Day-Ahead dispatch for each generator
Pg_real = Float64.(Pg_DA)       # Convert to Float64
Pg_real[8] = 0                  # Generator 8 failure
Pg_real[13:15] = 0.85 .* Pgmax[13:15]  # -15% for half of the wind farms
Pg_real[16:18] = 1.1 .* Pgmax[16:18]   # +10% for half of the wind farms
Pd_DA = Pd_values             # Day-Ahead demand

# 2) Define Up and Down costs for conventional generators (based on Day-Ahead price and production cost)
cost_up = Vector{Float64}(undef, G)
cost_down = Vector{Float64}(undef, G)

# Upward regulation price = Day-ahead price + 10% of production cost
for g in 1:12  # Only flexible conventional generators (assuming the 6 most expensive ones are flexible)
    cost_up[g] = Offer_Price[g] + 0.1 * Offer_Price[g]  # 10% of production cost
end

# Downward regulation price = Day-ahead price - 15% of production cost
for g in active_generators  # Only active generators that are producing
    cost_down[g] = Offer_Price[g] - 0.15 * Offer_Price[g]  # 15% of production cost
end

#println("Up Costs: ", cost_up)
#println("Down Costs: ", cost_down)


# 3) Create a new JuMP model for the Balancing Market
m_balance = Model(Gurobi.Optimizer)

# 4) Decision variables:
#    up[g]:   how much extra power (above Day-Ahead dispatch) each generator g produces
#    down[g]: how much power each generator g reduces from its Day-Ahead dispatch
#    curt:    load curtailment (in MWh), representing the amount of demand not served
@variable(m_balance, up[1:G] >= 0)
@variable(m_balance, down[1:G] >= 0)
@variable(m_balance, curt >= 0)

# 5) Objective function: minimize the total balancing cost
#    up[g] is charged at cost_up[g], down[g] at cost_down[g], and load curtailment costs €500/MWh
@objective(m_balance, Min,
    sum(up[g] * cost_up[g] for g in 1:G) + sum(down[g] * cost_down[g] for g in 1:G) + 500 * curt
)

# 6) Constraints

# a) Balance constraint (supply meets demand minus curtailment):
#    sum of all (Day-Ahead + up - down) must cover Day-Ahead demand minus curtailed load
@constraint(m_balance, balance_bal,
    sum(Pd_DA) - curt == sum(Pg_real[g] + up[g] - down[g] for g in 1:G)
)

# b) Up/Down must not exceed technical generator limits respecting Day Ahead schedule:
@constraint(m_balance, [g = 1:G],
    0 <= up[g] <= Pgmax[g] - Pg_DA[g])

@constraint(m_balance, [g = 1:G],
    0 <= down[g] <= Pg_DA[g]
)

# A generator cannot produce below 0:
@constraint(m_balance, [g = 1:G],
    Pg_DA[g] + up[g] - down[g] >= 0
)

# c) curtailment must not exceed total demand
@constraint(m_balance, 0 <= curt <= sum(Pd_DA))

# d) Generator 8 is out of service
@constraint(m_balance, up[8] == 0)
@constraint(m_balance, down[8] == 0)

# e) wind farms and cheap generators (offer price < 10) cannot offer Up/Down regulation
@constraint(m_balance, [g = G_unflex],
    up[g] == 0
)
@constraint(m_balance, [g = G_unflex],
    down[g] == 0
)

# 7) Solve the Balancing model
optimize!(m_balance)

# 8) Retrieve and display Balancing results
println("_________________Results for Balancing Market:________________")
if termination_status(m_balance) == MOI.OPTIMAL
    up_val = value.(up)
    down_val = value.(down)
    curt_val = value(curt)

    println("Up-Regulation per Generator:   ", up_val)
    println("Down-Regulation per Generator: ", down_val)
    println("Load Curtailment:             ", curt_val, " MWh")

    # Total balancing cost (objective value)
    bal_cost = objective_value(m_balance)
    println("Total Balancing Cost: ", bal_cost, " €")

    # Optional: the balancing price can be taken from the dual of the balance constraint.
    # Caution: sign and interpretation can vary; in some cases you might need to use -dual(...).
    bal_price = dual(balance_bal)
    println("Balancing Price (shadow price): ", abs(bal_price))

else
    println("Balancing model did not converge!")
end

# Actual generation after Balancing:
#    'up_val[g]' and 'down_val[g]' come from the solved Balancing model.
#    This is your real (final) production for generator g.
actual_generation = [
    Pg_real[g] + up_val[g] - down_val[g] for g in 1:G
]

##########################################
## One-Price Settlement
##########################################

# Suppose 'bal_price' is the single balancing price.
bal_price = abs(dual(balance_bal))

profit_oneprice = Vector{Float64}(undef, G)

for g in 1:G
    # Positive imbalance => generator produces more than DA => revenue
    # Negative imbalance => generator is short => cost
    imbalance = actual_generation[g] - Pg_DA[g]
    profit_oneprice[g] = imbalance * bal_price
end

# Total Profit under One-Price = Day-Ahead Profit + Balancing Profit
profit_oneprice_sorted = profit_oneprice[sorted_indices_offer]
total_profit_one_price_sorted = profit_DA_sorted .+ profit_oneprice_sorted


##########################################
## Two-Price Settlement
##########################################

# if power deficit: pay DA price for generators with excess (desired); 
#  pr_bal > pr_DA   charge balancing price for generators with deficit (undesired);
# if power excess:  charged DA price for generators with deficit (desired);
#  pr_bal < pr_DA   paid balancing price for generators with excess (undesired)

profit_twoprice = Vector{Float64}(undef, G)

# If the power system has a deficit
if sum(Pg_real) < sum(Pg_DA)
    println("Power System has a deficit!")
    for g in 1:G
        # Positive imbalance => generator produces more than DA => revenue
        # Negative imbalance => generator is short => cost
        imbalance = actual_generation[g] - Pg_DA[g]

        if imbalance >= 0               # Generator excess
            profit_twoprice[g] = imbalance * p_DA
        else                            # Generator deficit
            profit_twoprice[g] = imbalance * bal_price
        end
    end
end


# If the power system has an excess
if sum(Pg_real) > sum(Pg_DA)
    println("Power System has an excess!")
    for g in 1:G
        # Positive imbalance => generator produces more than DA => revenue at bal_price
        # Negative imbalance => generator is short => cost at DA_price
        imbalance = actual_generation[g] - Pg_DA[g]
        if imbalance >= 0               # Generator excess
            profit_twoprice[g] = imbalance * bal_price
        else                            # Generator deficit
            profit_twoprice[g] = imbalance * p_DA
        end
    end
end
# For the case that the power system has a deficit


# Total Profit under Two-Price = Day-Ahead Profit + Balancing Profit
profit_twoprice_sorted = profit_twoprice[sorted_indices_offer]
total_profit_two_price = profit_DA_sorted .+ profit_twoprice_sorted

println("Total Profit in Day-Ahead Market: ", round.(profit_DA_sorted, digits=2))
println("Total Profit under One-Price Settlement: ", round.(total_profit_one_price_sorted, digits=2))
println("Total Profit under Two-Price Settlement: ", round.(total_profit_two_price, digits=2))
