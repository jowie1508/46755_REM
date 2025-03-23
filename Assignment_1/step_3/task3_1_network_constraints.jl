########################
# This script contains the code for Step 3: Network constraints - Nodal Market Prices
# and is introducing a nodal market prices by including network constraints
# In the first part, the initial data is loaded and some market settings printed out.
# The second part contains the optimization problem of the zonal day ahead market.
# The third part is displaying the results of the optimization and the system setup 
# along the congestion level of the lines

########################
# Imports
########################

using JuMP
import Pkg
using Gurobi
using DataFrames
using PrettyTables


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
# Set capacity to x on line 14->16
C_matrix[16, 14] = 50
C_matrix[14, 16] = 50

## Create Optimization Model
m = Model(Gurobi.Optimizer)

# 1. Decision Variables
@variable(m, 0 <= Pd[d=1:D] <= Pdmax[d])        # Demand per node
@variable(m, 0 <= Pg[g=1:G] <= Pgmax[g])        # Generation per generator
@variable(m, theta[i=1:num_buses])              # Voltage angles at each bus
@variable(m, F[i=1:num_buses, j=1:num_buses])   # Power flow on transmission lines

# 2. Objective Function
@objective(m, Max, sum(Bid_Price[d] * Pd[d] for d in 1:D) - sum(Offer_Price[g] * Pg[g] for g in 1:G))

# 2. Constraints
@constraint(m, [d=1:D], 0 <= Pd[d] <= Pdmax[d])  # Demand constraints
@constraint(m, [g=1:G], 0 <= Pg[g] <= Pgmax[g])  # Generation constraints

power_balance = @constraint(m, [i=1:num_buses],     # Power Balance constraint
    sum(Pg[g] for g in 1:G if bus_g[g] == i) +                      
    sum(F[j, i] for j in 1:num_buses if C_matrix[j, i] > 0) -       
    sum(Pd[d] for d in 1:D if bus_d[d] == i) -                      
    sum(F[i, j] for j in 1:num_buses if C_matrix[i, j] > 0) == 0    
)

@constraint(m, [i in 1:num_buses, j in 1:num_buses; C_matrix[i, j] > 0], # DC Power Flow constraint
    F[i, j] == B_matrix[i, j] * (theta[i] - theta[j]))

@constraint(m, [i in 1:num_buses, j in 1:num_buses; C_matrix[i, j] > 0], # Line capacity constraint
    -C_matrix[i, j] <= F[i, j] <= C_matrix[i, j])

@constraint(m, [i in 1:num_buses, j in 1:num_buses; C_matrix[i, j] > 0], # Slack bus constraint
    -C_matrix[i, j] <= F[i, j] <= C_matrix[i, j])

# 3. solve model
optimize!(m)

# 4. Print Results
println("===============================================")
println("            MARKET CLEARING RESULTS           ")
println("===============================================")

# Market Clearing Prices (Nodal LMPs)
nodal_prices = [dual(power_balance[i]) for i in 1:num_buses]

# Total Generation and Demand
total_generation = sum(value(Pg[g]) for g in 1:G)
total_demand = sum(value(Pd[d]) for d in 1:D)

# Total Social Welfare
println("Total Social Welfare: $(round(objective_value(m), digits=2)) €")
println("===============================================")

# Extract computed values
optimal_generation = value.(Pg)
optimal_demand = value.(Pd)

# Initialize arrays with empty lists instead of single values
bus_generation = [Float64[] for _ in 1:num_buses]  
bus_demand = [Float64[] for _ in 1:num_buses]  
bus_max_generation = [Float64[] for _ in 1:num_buses]  
bus_max_demand = [Float64[] for _ in 1:num_buses]  
bus_offer_price = [Float64[] for _ in 1:num_buses]  
bus_bid_price = [Float64[] for _ in 1:num_buses]  

# Store lists of generator values for each bus
for g in 1:G
    bus_index = bus_g[g]
    push!(bus_generation[bus_index], round(optimal_generation[g], digits=2))
    push!(bus_max_generation[bus_index], Pgmax[g])
    push!(bus_offer_price[bus_index], Offer_Price[g])
end

# Store lists of demand values for each bus
for d in 1:D
    bus_index = bus_d[d]
    push!(bus_demand[bus_index], round(optimal_demand[d], digits=2))
    push!(bus_max_demand[bus_index], Pdmax[d])
    push!(bus_bid_price[bus_index], Bid_Price[d])
end

# Ensure all buses have lists (avoid `nothing` errors)
for i in 1:num_buses
    if isempty(bus_generation[i]) bus_generation[i] = Float64[] end
    if isempty(bus_max_generation[i]) bus_max_generation[i] = Float64[] end
    if isempty(bus_offer_price[i]) bus_offer_price[i] = Float64[] end
    if isempty(bus_demand[i]) bus_demand[i] = Float64[] end
    if isempty(bus_max_demand[i]) bus_max_demand[i] = Float64[] end
    if isempty(bus_bid_price[i]) bus_bid_price[i] = Float64[] end
end

# Create a structured DataFrame
structured_df = DataFrame(
    "Bus Number" => 1:num_buses,
    "Nodal LMP (€/MWh)" => round.(nodal_prices, digits=4),
    "Optimal Generation (MW)" => bus_generation,
    "Max Generation (MW)" => bus_max_generation,
    "Offer Price (€/MWh)" => bus_offer_price,
    "Optimal Demand (MW)" => bus_demand,
    "Max Demand (MW)" => bus_max_demand,
    "Bid Price (€/MWh)" => bus_bid_price
)

show(structured_df, allrows=true, allcols=true)
println("\n===============================================")

# Initialize variables for tracking the most congested line
max_congestion_ratio = 0
most_congested_lines = []
congested_lines_found = false  # Flag to check if any lines are ≥90% congested

println("\n===============================================")
println("       ⚠ CONGESTED TRANSMISSION LINES ⚠        ")
println("===============================================")

for I in keys(C_matrix)  # Iterate over all transmission lines
    (i, j) = Tuple(I)  # Convert CartesianIndex to a tuple

    if C_matrix[i, j] > 0  # Only consider lines with valid capacity
        flow = round(value(F[i, j]), digits=2)
        capacity = C_matrix[i, j]
        congestion_ratio = abs(flow) / capacity  # Compute congestion percentage

        # Ensure global variables are updated inside the loop
        global max_congestion_ratio
        global most_congested_lines

        if congestion_ratio >= 0.9  # Only print lines that are at least 90% congested
            congested_lines_found = true
            println("Line ($i → $j): Flow = $flow MW / Capacity = $capacity MW  [$(round(congestion_ratio * 100, digits=2))% Congested]")

        # Track the most congested line(s)
        if congestion_ratio > max_congestion_ratio
            max_congestion_ratio = congestion_ratio
            most_congested_lines = [(i, j, congestion_ratio)]  # Reset list with new max
        elseif congestion_ratio == max_congestion_ratio
            push!(most_congested_lines, (i, j, congestion_ratio))  # Add to list if tied
        end
    end

    # Always track the most congested line, even if it's <90%
    if congestion_ratio > max_congestion_ratio
        max_congestion_ratio = congestion_ratio
        most_congested_lines = [(i, j, congestion_ratio)]  # Reset list with new max
    elseif congestion_ratio == max_congestion_ratio
        push!(most_congested_lines, (i, j, congestion_ratio))  # Add to list if tied
    end
  end
end

# If no lines were ≥90% congested, still display the most congested one
if !congested_lines_found
    println("\nNo lines are critically congested (≥90% usage), but the most congested line(s) are:")
end

# Print the most congested transmission line(s)
println("\n===============================================")
println("       ⚠ MOST CONGESTED TRANSMISSION LINE(S) ⚠ ")
println("===============================================")
for (i, j, congestion_ratio) in most_congested_lines
    println("Line ($i → $j) is the MOST congested: $(round(congestion_ratio * 100, digits=2))% capacity used.")
end

println("\n⚡ Power Flow on Transmission Lines (Uncongested Case) ⚡")
for I in keys(C_matrix)  # Iterate over all keys in the capacity matrix
    (i, j) = Tuple(I)  # Convert CartesianIndex to a tuple
    if value(F[i, j]) > 0
        println("Line ($i → $j): Flow = $(round(value(F[i, j]), digits=2)) MW / Capacity = $(C_matrix[i, j]) MW")
    end
end

println("\n⚠ Identifying Key Transmission Lines for Sensitivity Analysis ⚠")

for I in keys(C_matrix)  # Iterate over all transmission line keys
    (i, j) = Tuple(I)  # Convert CartesianIndex to a tuple

    flow = abs(value(F[i, j]))  # Get power flow value
    capacity = C_matrix[i, j]  # Get transmission capacity
    utilization = (flow / capacity) * 100  # Compute utilization percentage

    if utilization > 40  # Only consider lines with >50% utilization
        println("🔹 Line ($i → $j): Flow = $flow MW / Capacity = $capacity MW  [$(round(utilization, digits=2))% Utilized]")
    end
end


