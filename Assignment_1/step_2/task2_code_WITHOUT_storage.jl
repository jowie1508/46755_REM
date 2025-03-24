# =============================================================================
# Task 1: Electricity Market WITHOUT Battery Storage
# -----------------------------------------------------------------------------
# Use:
#     Models a simplified 24-hour electricity market optimization problem 
#     without battery storage. Maximizes social welfare by matching generator 
#     supply and consumer demand under capacity constraints.
#
# Type:
#     Linear optimization model using JuMP and Gurobi.
#
# Input:
#     - Generator offer prices and production capacity matrix
#     - Consumer bid prices and demand limits
#     - Time horizon of 24 hours
#
# Function:
#     Solves for:
#         • Optimal generation and demand schedules
#         • Market-clearing prices (dual of balance constraints)
#         • Generator profits
#         • Total social welfare
#
# Output:
#     - Generator-wise profit (€)
#     - Total social welfare (€)
#     - Hourly market-clearing prices (€/MWh)
#     - Optional plot for market price trend
# =============================================================================

using JuMP
using Gurobi
using CSV, DataFrames
using Plots

include("get_data.jl")  # Load helper functions

### ------------------ Load Input Data ------------------ ###
Bid_Price_Matrix = generate_bid_prices()
generator_df, generator_matrix = generate_generator_matrix("wind_data/power_output_matrix.csv")
Pdmax_matrix = generate_demand_loads()

Offer_Price = [12.3; 12.3; 19; 19; 24; 9.7; 9.7; 5.5; 5; 0; 9.7; 10; 0; 0; 0; 0; 0; 0]

G = 18
D = 17
T = 24

model = Model(Gurobi.Optimizer)

@variable(model, 0 <= Pd[1:T, 1:D])
@variable(model, 0 <= Pg[1:T, 1:G])

@objective(model, Max,
    sum(Bid_Price_Matrix[t,d] * Pd[t,d] for t in 1:T, d in 1:D) -
    sum(Offer_Price[g] * Pg[t,g] for t in 1:T, g in 1:G)
)

@constraint(model, [t in 1:T, g in 1:G], Pg[t,g] <= generator_matrix[t,g])
@constraint(model, [t in 1:T, d in 1:D], Pd[t,d] <= Pdmax_matrix[t,d])
@constraint(model, balance[t in 1:T],
    sum(Pd[t,d] for d in 1:D) == sum(Pg[t,g] for g in 1:G)
)

optimize!(model)

market_prices_without = [abs(dual(balance[t])) for t in 1:T]

### ------------------ Results ------------------ ###
market_prices_without = [abs(dual(balance[t])) for t in 1:T]
social_welfare = objective_value(model)

println("Social Welfare WITHOUT Battery: €", round(social_welfare, digits=2))

println("Generator Profits (Without Battery):")

# Generator profits
generator_profit = zeros(G)
for g in 1:G, t in 1:T
    generator_profit[g] += (market_prices_without[t] - Offer_Price[g]) * value(Pg[t, g])
end

# Sort generator profits by offer price
sorted_indices_offer = sortperm(Offer_Price)
generator_profit_sorted = generator_profit[sorted_indices_offer]

# Print generator-wise profits
println("Generator Profits:")
for g in 1:G
    println("  Generator $g Profit: €", round(generator_profit_sorted[g], digits=2))
end

println("Total Social Welfare: €", round(social_welfare, digits=2))
  ### ------------------ Optional Plot ------------------ ###
    # Uncomment to visualize market prices
    # plot(1:T, market_prices, seriestype=:steppost, marker=:o,
    #     xlabel="Hour", ylabel="€/MWh", title="Market Prices Without Battery")
    # savefig("market_price_without_battery.png")


