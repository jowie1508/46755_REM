using Plots, DataFrames, CSV, JuMP, Gurobi

# Include the Julia files (ensure they are in the same directory)
include("task2_code_WITHOUT_storage.jl")
include("task2_code_WITH_storage.jl")

# Extract market-clearing prices from each file
market_prices_without_storage = market_prices_without  # Ensure correct variable name
market_prices_with_storage = market_prices_with  # Ensure correct variable name

# Define hours (1 to 24)
hours = 1:24

# Create the base plot (With Storage)
p = plot(
    hours, market_prices_with_storage, 
    label="With Storage", 
    marker=:circle, linewidth=2, 
    linecolor=:blue, markercolor=:blue, markersize=5, 
    linestyle=:solid, alpha=0.8,
    seriestype=:steppost,
    ylims=(5, 13)  #  Keep only this `seriestype`
)

# Overlay the second plot (Without Storage)
plot!(
    hours, market_prices_without_storage, 
    label="Without Storage", 
    marker=:square, linewidth=2, 
    linecolor=:red, markercolor=:red, markersize=5, 
    linestyle=:dash, alpha=0.8,
    seriestype=:steppost
)

# Labels and Title
xlabel!("Time [h]")
ylabel!("Market Clearing Price [€/MWh]")
title!("Market Clearing Prices With and Without Storage")

# Save the figure (optional)
savefig("market_clearing_prices_comparison.png")

# Show the plot
display(p)


using Plots

# Time vector
time_hours = 1:T

# Convert SOC from MWh to %
SOC_percent = value.(E_stored) ./ 700 .* 100

# Plot with percentage-based y-axis
soc_plot = plot(
    time_hours, SOC_percent,
    label="State of Charge",
    lw=2,
    lc=:black,
    linestyle=:solid,
    marker=:none,
    xlabel="Time [h]",
    ylabel="SOC [%]",
    legend=:topright,
    title="Battery State of Charge",
    size=(700, 400),
    ylim=(0, 100)
)

# Display and save
display(soc_plot)
savefig(soc_plot, "battery_soc_percent.png")
