# =============================================================================
# Task 2: Electricity Market WITH Battery Storage
# -----------------------------------------------------------------------------
# Use:
#     This script models a 24-hour electricity market including a Li-ion battery 
#     using JuMP and Gurobi. The model maximizes social welfare by balancing 
#     generation, demand, and battery operation.
#
# Type:
#     Linear optimization model (social welfare maximization) with storage dynamics.
#
# Input:
#     - Bid prices per demand unit and hour
#     - Generator marginal costs and max hourly capacities
#     - Demand limits for each load point per hour
#     - Battery parameters: charge/discharge limits, efficiencies, energy capacity
#
# Function:
#     - Optimizes power generation and battery scheduling
#     - Enforces balance and storage constraints
#     - Calculates market-clearing prices from duals
#     - Computes profits for generators and battery arbitrage
#
# Outputs:
#     - Hourly market-clearing prices
#     - Generator profits
#     - Wind farm profits
#     - Battery profit
#     - Total social welfare
#     - Optional plots for diagnostics and visualization
# =============================================================================

using JuMP
using Gurobi
using CSV, DataFrames
using Plots

include("get_data.jl")  # Loads custom data functions

function main()
    ### ------------------ Load Input Data ------------------ ###
    Bid_Price_Matrix = generate_bid_prices()
    generator_df, generator_matrix = generate_generator_matrix("wind_data/power_output_matrix.csv")
    Pdmax_matrix = generate_demand_loads()

    ### ------------------ Battery Parameters ------------------ ###
    P_ch_max = 300
    P_disch_max = 350
    eff_ch = 0.92
    eff_disch = 0.96
    E_stored_capacity = 700

    ### ------------------ Generator Setup ------------------ ###
    Offer_Price = [
        12.3; 12.3; 19; 19; 24;
         9.7;  9.7; 5.5; 5; 0;
         9.7; 10; 0; 0; 0; 0; 0; 0
    ]

    G = 18
    D = 17
    T = 24

    ### ------------------ Build Optimization Model ------------------ ###
    m = Model(Gurobi.Optimizer)

    @variable(m, 0 <= Pd[1:T, 1:D])
    @variable(m, 0 <= Pg[1:T, 1:G])
    @variable(m, 0 <= p_ch[1:T] <= P_ch_max)
    @variable(m, 0 <= p_disch[1:T] <= P_disch_max)
    @variable(m, 0 <= E_stored[1:T] <= E_stored_capacity)

    @objective(m, Max,
        sum(Bid_Price_Matrix[t,d] * Pd[t,d] for t in 1:T, d in 1:D) -
        sum(Offer_Price[g] * Pg[t,g] for t in 1:T, g in 1:G)
    )

    @constraint(m, [t in 1:T, g in 1:G], Pg[t,g] <= generator_matrix[t,g])
    @constraint(m, [t in 1:T, d in 1:D], Pd[t,d] <= Pdmax_matrix[t,d])
    @constraint(m, balance[t in 1:T],
        sum(Pd[t,d] for d in 1:D) + p_ch[t] == sum(Pg[t,g] for g in 1:G) + p_disch[t]
    )
    @constraint(m, [t in 1:T],
        E_stored[t] == (t > 1 ? E_stored[t-1] : 0) + p_ch[t] * eff_ch - p_disch[t] / eff_disch
    )

    ### ------------------ Solve Model ------------------ ###
    optimize!(m)

    ### ------------------ Results ------------------ ###
    market_prices_with = [abs(dual(balance[t])) for t in 1:T]

    println("Hourly Market-Clearing Prices With Storage:")
    for t in 1:T
        println("  Hour $t: €", market_prices_with[t])
    end

    # Battery arbitrage profit
    battery_profit = sum(
        market_prices_with[t] * (value(p_disch[t]) - value(p_ch[t]))
        for t in 1:T
    )
    println("Battery Profit: €", round(battery_profit, digits=2))
    
    # Generator profits
    generator_profit = zeros(G)
    for g in 1:G, t in 1:T
        generator_profit[g] += (market_prices_with[t] - Offer_Price[g]) * value(Pg[t, g])
    end

    # Wind farm profit (generators with 0 cost)
    wind_farm_profit = 0.0
    for g in 1:G
        if Offer_Price[g] == 0
            for t in 1:T
                wind_farm_profit += market_prices_with[t] * value(Pg[t, g])
            end
        end
    end
    println("Wind Farm Total Profit: €", round(wind_farm_profit, digits=2))
    
    # Get the permutation indices to sort offer and Bid prices
    sorted_indices_offer = sortperm(Offer_Price)
    
    
    # Sort Prices and Pg/Pd values using the permutation indices
    generator_profit_sorted = generator_profit[sorted_indices_offer]
 

 
    # Print generator-wise profits
    println("Generator Profits:")
    for g in 1:G
        println("  Generator $g Profit: €", round(generator_profit_sorted[g], digits=2))
    end

    println("Total Social Welfare: €", round(objective_value(m), digits=2))

    ### ------------------ Optional Plotting ------------------ ###
    # Uncomment to generate plots

    # plot(1:T, value.(E_stored), lw=2, label="Battery SOC", xlabel="Time [h]",
    #     ylabel="Energy [MWh]", title="Battery State of Charge")
    # savefig("battery_soc_plot.png")

    # plot(1:T, market_prices_with, seriestype=:steppost, marker=:o, xlabel="Time [h]",
    #     ylabel="€/MWh", title="Market Prices With Battery", legend=false)
    # savefig("market_clearing_price_with_battery.png")
end

# Run the script
main()
