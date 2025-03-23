########################
# This script contains the code for Step 3: Network constraints - Sensitivity Analysis Part I
# and is investigating the impact of line congestion across the network on the market clearing results.
# In the first part, the initial data is loaded and some market settings printed out.
# The second part contains the optimization problem of the zonal day ahead market.
# The third part is displaying the results of the optimization and the system setup. 

########################
# Imports
########################

using JuMP
import Pkg
using Gurobi
using DataFrames
using PrettyTables
using CSV

## Functions
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

# Define bid prices for demand in €/MWh (NordPool data for 17 loads)
Bid_Price = [28; 26.4; 24.3; 22; 19.7; 18; 17.2; 17; 16.8; 15.4; 14.9; 14.1; 13.7; 13; 12.8; 12.4; 5]

# Number of demand loads
D = length(Bid_Price)

# Offer price for generators in €/MWh
Offer_Price = [12.3; 12.3; 19; 19; 24; 9.7; 9.7; 5.5; 5; 0; 9.7; 10; 0; 0; 0; 0; 0; 0]

# Number of generators
G = length(Offer_Price)

# Maximum power output for generators (MW)
Pgmax = [152; 152; 350; 591; 60; 155; 155; 400; 400; 300; 310; 350; 150; 120; 140; 100; 130; 110]

# Maximum demand for each load (MW)
Pdmax = [96; 86; 159; 65; 63; 121; 111; 151; 154; 171; 234; 171; 279; 88; 295; 161; 170]

# Define the set of nodes (buses) in a 24-bus system
buses = collect(1:24)  
num_buses = length(buses)

# Transmission lines: (from, to, reactance, capacity)
lines = [
    (1, 2, 0.0146, 175), (1, 3, 0.2253, 175), (1, 5, 0.0907, 350),
    (2, 4, 0.1356, 175), (2, 6, 0.205, 175), (3, 9, 0.1271, 175),
    (3, 24, 0.084, 400), (4, 9, 0.111, 175), (5, 10, 0.094, 350),
    (6, 10, 0.0642, 175), (7, 8, 0.0652, 350), (8, 9, 0.1762, 175),
    (8, 10, 0.1762, 175), (9, 11, 0.084, 400), (9, 12, 0.084, 400),
    (10, 11, 0.084, 400), (10, 12, 0.084, 400), (11, 13, 0.0488, 500),
    (11, 14, 0.0426, 500), (12, 13, 0.0488, 500), (12, 23, 0.0985, 500),
    (13, 23, 0.0884, 500), (14, 16, 0.0594, 500), (15, 16, 0.0172, 500),
    (15, 21, 0.0249, 1000), (15, 24, 0.0529, 500), (16, 17, 0.0263, 500),
    (16, 19, 0.0234, 500), (17, 18, 0.0143, 500), (17, 22, 0.1069, 500),
    (18, 21, 0.0132, 1000), (19, 20, 0.0203, 1000), (20, 23, 0.0112, 1000),
    (21, 22, 0.0692, 500)
]

# Initialize reactance & capacity matrices
X_matrix = fill(Inf, num_buses, num_buses)   
C_matrix = fill(0.0, num_buses, num_buses)   

# Populate matrices
for (i, j, reactance, capacity) in lines
    X_matrix[i, j] = reactance
    X_matrix[j, i] = reactance  
    C_matrix[i, j] = capacity
    C_matrix[j, i] = capacity  
end

# Compute susceptance (B = 1/X)
B_matrix = 1 ./ X_matrix
B_matrix[X_matrix .== Inf] .= 0  # Set non-existent lines to 0 susceptance

# Define Slack Bus (Reference Bus)
slack_bus = 13

# Generator locations
bus_g = Dict(
    1 => 1, 2 => 2, 3 => 7, 4 => 13, 5 => 15, 6 => 15, 7 => 16, 8 => 18,
    9 => 21, 10 => 22, 11 => 23, 12 => 23, 
    13 => 3, 14 => 5, 15 => 7, 16 => 16, 17 => 21, 18 => 23
)

# Demand locations
bus_d = Dict(
    1 => 1, 2 => 2, 3 => 3, 4 => 4, 5 => 5, 6 => 6, 7 => 7, 8 => 8, 
    9 => 9, 10 => 10, 11 => 13, 12 => 14, 13 => 15, 14 => 16, 15 => 18,
    16 => 19, 17 => 20
)

########################
# Optimization
########################

# Define congestion scenarios
scenarios = [50, 150, 200, 500]  # Inf represents no congestion

# Initialize results DataFrame before the loop
results_df = DataFrame("Bus Number" => Int[], "Nodal LMP (€/MWh)" => Float64[], "Line Capacity (MW)" => Float64[], "Congestion Level (MW)" => Float64[], "SW" => Float64[])

# Loop over each congestion level
for congestion in scenarios
    println("\n🚀 Running Simulation for Transmission Capacity = $congestion MW")

    
    C_matrix[16, 14] = congestion
    C_matrix[14, 16] = congestion


    ## Create Optimization Model
    m = Model(Gurobi.Optimizer)

    # 1. Decision Variables
    @variable(m, 0 <= Pd[d=1:D] <= Pdmax[d])       
    @variable(m, 0 <= Pg[g=1:G] <= Pgmax[g])        
    @variable(m, theta[i=1:num_buses])              
    @variable(m, F[i=1:num_buses, j=1:num_buses])   

    # 2. Objective Function
    @objective(m, Max, sum(Bid_Price[d] * Pd[d] for d in 1:D) - sum(Offer_Price[g] * Pg[g] for g in 1:G))

    # 3. Constraints
    power_balance = @constraint(m, [i=1:num_buses],  
        sum(Pg[g] for g in 1:G if bus_g[g] == i) +                      
        sum(F[j, i] for j in 1:num_buses if C_matrix[j, i] > 0) -       
        sum(Pd[d] for d in 1:D if bus_d[d] == i) -                      
        sum(F[i, j] for j in 1:num_buses if C_matrix[i, j] > 0) == 0    
    )

    @constraint(m, [i in 1:num_buses, j in 1:num_buses; C_matrix[i, j] > 0], 
        F[i, j] == B_matrix[i, j] * (theta[i] - theta[j]))

    @constraint(m, [i in 1:num_buses, j in 1:num_buses; C_matrix[i, j] > 0], 
        -C_matrix[i, j] <= F[i, j] <= C_matrix[i, j])

    @constraint(m, theta[slack_bus] == 0) 

    # 4. Solve model
    optimize!(m)

    # 5. Extract LMP values
    nodal_prices = dual.(power_balance)
    flow = round(value(F[14, 16]), digits=2)
    capacity = C_matrix[14, 16]
    congestion_ratio = abs(flow) / capacity  # Compute congestion percentage

    # Create temporary DataFrame
    temp_df = DataFrame(
        "Bus Number" => 1:num_buses,
        "Nodal LMP (€/MWh)" => round.(nodal_prices, digits=4),
        "Line Capacity (MW)" => congestion,
        "Congestion Level (MW)" => flow,
        "SW" => round(objective_value(m), digits=2)
    )

    println("Total Social Welfare: $(round(objective_value(m), digits=2)) €")

    # Append to master DataFrame
    append!(results_df, temp_df)
end

# Save results to CSV for later analysis
CSV.write("sensitivity_analysis_results.csv", results_df)
println("\nSensitivity Analysis Completed! Results saved to 'sensitivity_analysis_results.csv'")
