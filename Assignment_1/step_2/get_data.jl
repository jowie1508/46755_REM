# ============================================================================
# Input Data Functions for Electricity Market Model
# ----------------------------------------------------------------------------
# Use:
#     Provides input data matrices for a 24-hour electricity market simulation:
#     - Load bid prices (€/MWh)
#     - Maximum power demand per node
#     - Generator capacity (conventional + wind)
#
# Type:
#     Data preparation and transformation utilities for use in JuMP optimization models.
#
# Input:
#     - Hardcoded system demand and load allocation percentages
#     - Wind generator outputs from a CSV file (path provided as string)
#
# Function:
#     - generate_bid_prices(): creates a 24×17 bid price matrix (hour × load)
#     - generate_demand_loads(): creates a 24×17 Pdmax matrix of load caps
#     - generate_generator_matrix(wind_data_path): returns a 24×18 generation matrix (Pgmax)
#
# Outputs:
#     - Bid_Price_Matrix::Matrix{Float64}
#     - Pdmax_matrix::Matrix{Float64}
#     - Pgmax_matrix::Matrix{Float64}, Pgmax_df::DataFrame (for debugging/plotting)
# ============================================================================


using CSV, DataFrames

### ------------------ Load Bid Prices ------------------ ###
function generate_bid_prices()
    # Base bid prices per load (€/MWh), static across hours
    Bid_Price = [28; 26.4; 24.3; 22; 19.7; 18; 17.2; 17; 16.8;
                 15.4; 14.9; 14.1; 13.7; 13; 12.8; 12.4; 5]

    # Time-of-day price variation factors for 24 hours
    price_factors = [
        0.50, 0.48, 0.47, 0.60, 0.70,    # 0–4h: Overnight low
        1.10, 1.50, 1.90, 2.10, 1.70,    # 5–9h: Morning peak
        1.30, 1.10, 1.00, 0.95, 1.10,    # 10–14h: Midday valley
        1.60, 2.20, 2.70, 3.00, 3.00,    # 15–19h: Evening peak
        2.40, 1.70, 1.00, 0.70           # 20–23h: Ramp down
    ]

    # Multiply price factors by base bid prices (outer product)
    Bid_Price_Matrix = price_factors .* Bid_Price'

    # Round to 2 decimal places for readability
    Bid_Price_Matrix = round.(Bid_Price_Matrix, digits=2)

    println("Bid_Price_Matrix size: ", size(Bid_Price_Matrix))  # Should be (24,17)
    return Bid_Price_Matrix
end


### ------------------ Load Demand Caps ------------------ ###
function generate_demand_loads()
    # Total system demand per hour [MW]
    System_Demand_per_Hour = [
        1775.835, 1669.815, 1590.3, 1563.795, 1563.795, 1590.3,
        1961.37, 2279.43, 2517.975, 2544.48, 2544.48, 2517.975,
        2517.975, 2517.975, 2464.965, 2464.965, 2623.995, 2650.5,
        2650.5, 2544.48, 2411.955, 2199.915, 1934.865, 1669.815
    ]

    # Percentage of system demand allocated to each of the 17 load nodes
    system_load_percentage = [
        0.038, 0.034, 0.063, 0.026, 0.025, 0.048, 0.044, 0.06, 0.061,
        0.068, 0.093, 0.068, 0.111, 0.06, 0.117, 0.064, 0.045
    ]

    # Element-wise multiplication (24x1) ⋅ (1x17) → (24x17)
    Pdmax_matrix = System_Demand_per_Hour .* system_load_percentage'

    # Round to 2 decimal places
    Pdmax_matrix = round.(Pdmax_matrix, digits=2)

    return Pdmax_matrix
end


### ------------------ Load Generator Capacities ------------------ ###
function generate_generator_matrix(wind_data_path::String)
    # Max output (MW) of 12 conventional units
    conventional_unit = [152; 152; 350; 591; 60; 155; 155; 400; 400; 300; 310; 350]

    # Repeat same capacity for all 24 hours → matrix shape (24×12)
    conventional_matrix = repeat(conventional_unit, 1, 24)'

    # For debugging or visual inspection
    conventional_df = DataFrame(conventional_matrix, :auto)

    # Load wind generation data from CSV (expected 24×6 matrix)
    wind_data = CSV.read(wind_data_path, DataFrame; header=false)
    wind_matrix = Matrix(wind_data)

    # Dimension checks (to catch CSV formatting issues)
    @assert size(conventional_matrix) == (24, 12) "Conventional matrix should be (24,12)"
    @assert size(wind_matrix) == (24, 6) "Wind matrix should be (24,6)"

    # Combine horizontally: (24×12) ⊕ (24×6) → (24×18)
    Pgmax_matrix = hcat(conventional_matrix, wind_matrix)

    # Optional: DataFrame view for debugging
    Pgmax_df = DataFrame(Pgmax_matrix, :auto)

    return Pgmax_df, Pgmax_matrix
end
