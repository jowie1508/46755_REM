using Plots

# Find equilibrium price
function stepwise_lookup(x_vals, y_vals, x_query)
    idx = findlast(i -> x_vals[i] <= x_query, eachindex(x_vals))
    return isnothing(idx) ? nothing : y_vals[idx]
end

function plot_curve(supply_price, supply_quantity, demand_price, demand_quantity)
    # Step 1: sort supply and demand curves
    demand_order = sortperm(demand_price, rev=true)  # Get indices for sorting in descending order
    demand_price = demand_price[demand_order]
    demand_quantity = demand_quantity[demand_order]

    supply_order = sortperm(supply_price)  # Get indices for sorting in ascending order
    supply_price = supply_price[supply_order]
    supply_quantity = supply_quantity[supply_order]

    # Step 2: create cumulative list for quantities
    cumulative_demand = cumsum(demand_quantity)
    cumulative_supply = cumsum(supply_quantity)

    # Step 3: Generate Stepwise data
    demand_q_step, demand_p_step = stepwise_curve(cumulative_demand, demand_price)
    supply_q_step, supply_p_step = stepwise_curve(cumulative_supply, supply_price)

    # Step 4: Add a final point to the demand curve to connect to the x-axis
    push!(demand_q_step, demand_q_step[end])
    push!(demand_p_step, 0)

    # Create a plot
    p = plot(demand_q_step, demand_p_step, label="demand", linewidth=1, linecolor=:blue, linestyle=:solid)
    plot!(supply_q_step, supply_p_step, label="supply", linewidth=1, linecolor=:red, linestyle=:solid)

    # Add small circles at each supply curve data point
    scatter!(supply_q_step, supply_p_step, label="", color=:red, markersize=1, markerstrokewidth=0.5)
    scatter!(demand_q_step, demand_p_step, label="", color=:blue, markersize=1, markerstrokewidth=0.5)
    # Labels and title
    xlabel!("quantity [MW]")
    ylabel!("price [€]")

    equilibrium = stepwise_lookup(supply_q_step, supply_p_step, demand_q_step[end])  # Find equilibrium price
    println("Equilibrium Price: ", equilibrium)
    scatter!([demand_q_step[end]], [equilibrium], label="point of equilibrim", color=:green, markersize=3)  # Add intersection point


    display(current())  # show plot

    savefig(p, "supply_demand_curve.png")  # Save plot
end