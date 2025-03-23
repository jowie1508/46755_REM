########################
# This script contains the code for Step 3: Network constraints - Zonal Feasibility
# In the first part, the initial data is loaded and some market settings printed out.
# The second part contains the optimization problem of the zonal day ahead market.
# The third part is displaying the results of the optimization and the system setup and 
# displays wether lines within the zones are critically congested or overloaded
########################
# Imports
########################

using JuMP
using Gurobi
using DataFrames, PrettyTables
using LinearAlgebra

########################
# Initial Setup
########################

# Define bid prices for demand in €/MWh (NordPool data for 17 loads)
Bid_Price = [28; 26.4; 24.3; 22; 19.7; 18; 17.2; 17; 16.8; 15.4; 14.9; 14.1; 13.7; 13; 12.8; 12.4; 11.2]

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

# Divide the 24-bus system into North and South zones
zones = Dict(
    "North" => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 24],
    "South" => [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
)

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

# Define Available Transfer Capacities (ATC) between zones with ATC Factor
ATC_factor = 1
ATC = Dict(
    ("North", "South") => ATC_factor * sum(capacity for (i, j, _, capacity) in lines if (i in zones["North"]) && (j in zones["South"]))
)
ATC["South", "North"] = ATC["North", "South"]
# Define zonal demand and generation
zonal_demand = Dict(
    "North" => sum(Pdmax[d] for d in 1:D if bus_d[d] in zones["North"]),
    "South" => sum(Pdmax[d] for d in 1:D if bus_d[d] in zones["South"])
)

zonal_generation = Dict(
    "North" => sum(Pgmax[g] for g in 1:G if bus_g[g] in zones["North"]),
    "South" => sum(Pgmax[g] for g in 1:G if bus_g[g] in zones["South"])
)

# Print initial zonal setup
println("\n==================== Zonal System Setup ====================")
println("Zones and their assigned buses:")
for (zone, buses) in zones
    println("$zone: $buses")
end

println("\n==================== Average Prices per Zone ====================")

avg_bid_price = Dict(
    zone => sum(Bid_Price[d] for d in 1:D if bus_d[d] in zones[zone]) / max(1, sum(1 for d in 1:D if bus_d[d] in zones[zone]))
    for zone in keys(zones)
)

avg_offer_price = Dict(
    zone => sum(Offer_Price[g] for g in 1:G if bus_g[g] in zones[zone]) / max(1, sum(1 for g in 1:G if bus_g[g] in zones[zone]))
    for zone in keys(zones)
)

println("Zonal Average Bid Prices (€/MWh):")
for (zone, price) in avg_bid_price
    println("$zone: $(round(price, digits=2)) €/MWh")
end

println("\nZonal Average Offer Prices (€/MWh):")
for (zone, price) in avg_offer_price
    println("$zone: $(round(price, digits=2)) €/MWh")
end

println("\nAvailable Transfer Capacities (ATC) between zones:")
for ((z1, z2), capacity) in ATC
    println("$z1 ↔ $z2: $capacity MW")
end

println("\nZonal Demand (MW):")
for (zone, demand) in zonal_demand
    println("$zone: $demand MW")
end

println("\nZonal Generation Capacity (MW):")
for (zone, generation) in zonal_generation
    println("$zone: $generation MW")
end

########################
# Optimization
########################

println("\n==================== Optimization ====================")
# Create Optimization Model
m = Model(Gurobi.Optimizer)

# Define Decision Variables
@variable(m, 0 <= Pd[d=1:D] <= Pdmax[d])        # Demand per node
@variable(m, 0 <= Pg[g=1:G] <= Pgmax[g])        # Generation per generator
@variable(m, Fz[z1 in keys(zonal_demand), z2 in keys(zonal_demand); z1 != z2], lower_bound=-get(ATC, (z1, z2), 0), upper_bound=get(ATC, (z1, z2), 0)) # transmission between zones

# Objective Function: Maximize Social Welfare
@objective(m, Max, sum(Bid_Price[d] * Pd[d] for d in 1:D) - sum(Offer_Price[g] * Pg[g] for g in 1:G if Pgmax[g] > 0))

# Constraints
@constraint(m, [d=1:D], 0 <= Pd[d] <= Pdmax[d])  # Demand constraints
@constraint(m, [g=1:G], 0 <= Pg[g] <= Pgmax[g])  # Generation constraints

# Power balance constraints for both zones
power_balance = Dict()
power_balance["North"] = @constraint(m, 
    sum(Pg[g] for g in 1:G if bus_g[g] in zones["North"]) 
    - sum(Pd[d] for d in 1:D if bus_d[d] in zones["North"]) 
    + Fz["North", "South"] == 0
)

power_balance["South"] = @constraint(m, 
    sum(Pg[g] for g in 1:G if bus_g[g] in zones["South"]) 
    - sum(Pd[d] for d in 1:D if bus_d[d] in zones["South"]) 
    + Fz["South", "North"] == 0
)

# ATC Constraint 
@constraint(m, -ATC["North", "South"] <= Fz["North", "South"] <= ATC["North", "South"])
@constraint(m, Fz["South", "North"] == -Fz["North", "South"])

println("\n===============================================")
println("            OPTIMIZING          ")
# Solve Model
optimize!(m)

println("\n==================== Checking Intra-Zonal Feasibility ====================")
total_generation = sum(value(Pg[g]) for g in 1:G)
total_demand = sum(value(Pd[d]) for d in 1:D)
total_net_injection = sum(bus_injections[i] for i in 1:24)

println("\n===== Total Power Balance Check =====")
println("Total Generation: ", round(total_generation, digits=2), " MW")
println("Total Demand: ", round(total_demand, digits=2), " MW")
println("Total Net Injection: ", round(total_net_injection, digits=2), " MW (should be 0)")

bus_generation = Dict(i => sum(value(Pg[g]) for g in 1:G if bus_g[g] == i; init=0) for i in 1:24)
bus_demand = Dict(i => sum(value(Pd[d]) for d in 1:D if bus_d[d] == i; init=0) for i in 1:24)
bus_injections = Dict(i => bus_generation[i] - bus_demand[i] for i in 1:24)

# Print for debugging
println("\n===== Bus-wise Power Injections & Connected Lines =====")
for i in 1:24
    gen = bus_generation[i]   # Extract generation at bus i
    demand = bus_demand[i]    # Extract demand at bus i
    net_injection = gen - demand  # Compute net injection

    println("Bus $i: Generation = $(round(gen, digits=2)) MW, Demand = $(round(demand, digits=2)) MW, Net Injection = $(round(net_injection, digits=2)) MW")

    # Print connected lines
    println("   ↳ Connected Lines:")
    for (from, to, _, capacity) in lines
        if from == i || to == i
            println("     - Bus $from ⇄ Bus $to (Capacity: $(capacity) MW)")
        end
    end
end

########################
# Results
########################

# Print Results
println("\n===============================================")
println("            ZONAL MARKET CLEARING RESULTS           ")
println("===============================================")
println("Total Social Welfare: $(round(objective_value(m), digits=2)) €")
println("===============================================")


# Market Clearing Prices (Zonal Prices)
println("\nZonal Market Prices (€/MWh):")
zonal_prices = Dict(zone => dual(power_balance[zone]) for zone in keys(zonal_demand))

for (zone, price) in zonal_prices
    println("$zone: $(round(price, digits=4)) €/MWh")
end

# Extract and Print Optimal Generation and Demand
# Extract individual generator outputs
optimal_generation_per_generator = Dict(g => value(Pg[g]) for g in 1:G)

# Extract individual demand consumption
optimal_demand_per_demand = Dict(d => value(Pd[d]) for d in 1:D)

# Aggregate generation per zone
optimal_generation_per_zone = Dict(zone => sum(value(Pg[g]) for g in 1:G if bus_g[g] in zones[zone]) for zone in keys(zonal_generation))

# Aggregate demand per zone
optimal_demand_per_zone = Dict(zone => sum(value(Pd[d]) for d in 1:D if bus_d[d] in zones[zone]) for zone in keys(zonal_demand))

println("\nOptimal Generation (MW):")
for (zone, generation) in optimal_generation_per_zone
    println("$zone: $(round(generation, digits=2)) MW")
end

println("\nOptimal Demand (MW):")
for (zone, demand) in optimal_demand_per_zone
    println("$zone: $(round(demand, digits=2)) MW")
end

# Print Power Flow Between Zones
println("\nInter-Zonal Power Flow:")
println("North → South: $(round(value(Fz["North", "South"]), digits=2)) MW")
println("ATC-Factor: ", ATC_factor)
