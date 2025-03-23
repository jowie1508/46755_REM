using Plots

function stepwise_lookup(x_vals, y_vals, x_query)
    idx = findlast(i -> x_vals[i] <= x_query, eachindex(x_vals))
    return isnothing(idx) ? nothing : y_vals[idx]
end

function plot_curve_with_reserve(supply_price, supply_quantity_original, supply_quantity_adjusted, demand_price, demand_quantity)
    # Step 1: Sort supply and demand curves
    demand_order = sortperm(demand_price, rev=true)
    demand_price = demand_price[demand_order]
    demand_quantity = demand_quantity[demand_order]

    supply_order = sortperm(supply_price)
    supply_price_sorted = supply_price[supply_order]
    supply_quantity_original_sorted = supply_quantity_original[supply_order]
    supply_quantity_adjusted_sorted = supply_quantity_adjusted[supply_order]

    # Step 2: Cumulative quantities
    cumulative_demand = cumsum(demand_quantity)
    cumulative_supply_original = cumsum(supply_quantity_original_sorted)
    cumulative_supply_adjusted = cumsum(supply_quantity_adjusted_sorted)

    # Step 3: Stepwise data
    demand_q_step, demand_p_step = stepwise_curve(cumulative_demand, demand_price)
    supply_q_step_original, supply_p_step = stepwise_curve(cumulative_supply_original, supply_price_sorted)
    supply_q_step_adjusted, _ = stepwise_curve(cumulative_supply_adjusted, supply_price_sorted)

    # Step 4: Add final point to demand curve to connect to x-axis
    push!(demand_q_step, demand_q_step[end])
    push!(demand_p_step, 0)

    # Plot everything
    p = plot(demand_q_step, demand_p_step, label="Demand Curve", linewidth=2, color=:blue, size=(800, 500))

    plot!(supply_q_step_original, supply_p_step, label="Supply (No Reserve)", linewidth=2, linestyle=:solid, color=:green)
    plot!(supply_q_step_adjusted, supply_p_step, label="Supply (With Reserve)", linewidth=2, linestyle=:dash, color=:red)

    xlabel!("Quantity (MW)")
    ylabel!("Price (€/MWh)")
    title!("Supply & Demand Curve With/Without Reserve Market")
#    legend(:topright)

    # Optional: mark example equilibrium
    scatter!([2408], [10], label="Equilibrium", color=:black, marker=:diamond, markersize=5)

    savefig(p, "supply_demand_comparison.png")
    display(p)
end
