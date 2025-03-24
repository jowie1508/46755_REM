Power Market Optimization using JuMP and Gurobi
This program models a simplified electricity market to determine the optimal power dispatch and market-clearing price by maximizing social welfare—the difference between consumer utility and generator cost.

Features
Models supply and demand curves using stepwise bids and offers

Solves a welfare-maximizing optimization problem using the Gurobi solver

Enforces capacity and power balance constraints

Estimates market-clearing price (λ)

Calculates:
	Generator profits
	Consumer utilities
	Total social welfare

Visualizes demand and supply curves

Requirements
Julia (version 1.6+ recommended)

Packages:
	JuMP
	Gurobi

A plotting module (plot_demand_supply.jl) to create the supply and demand curve

Gurobi installation and license

How to Run
	Make sure Gurobi is properly installed and licensed.

	Include your plotting module plot_demand_supply.jl in the same directory.

	Run the script in Julia

Output
The program prints:
	Estimated market-clearing price (€/MWh)
	Total social welfare (€)
	Profit for each generator (€)
	Utility for each demand load (€)
	All monetary values are displayed with two decimal precision.

Notes
	Data used (bid/offer prices and capacities) is based on an academic case study.

	The model currently assumes a static (single-period) market without time-dependence.