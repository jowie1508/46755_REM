Power Market Clearing and Balancing Simulation
This Julia script simulates a two-stage electricity market consisting of:

Day-Ahead Market: Clears supply and demand by maximizing social welfare based on submitted generator offers and consumer bids.

Balancing Market: Reacts to real-time deviations such as generator failures and renewable fluctuations, minimizing cost through up/down regulation and curtailment.

Features
	Linear optimization using JuMP and Gurobi

	Day-Ahead market clearing and price discovery

	Generator flexibility and real-time balancing

	One-price and two-price settlement mechanisms

	Profit and utility analysis for all participants

	Results formatted with two-decimal precision

Inputs
	Bid_Price: Consumer bid prices (€/MWh)

	Offer_Price: Generator offer prices (€/MWh)

	Pgmax: Generator capacity limits (MWh)

	Pdmax: Consumer maximum demand (MWh)

	G_unflex: List of non-flexible generators excluded from balancing

Outputs
	Market clearing prices (Day-Ahead and Balancing)

	Generator dispatch and demand allocation

	Generator profits and consumer utilities

	Total social welfare and balancing costs

	Profit comparison under different settlement rules

Dependencies
	JuMP.jl

	Gurobi.jl (requires valid license)

	plot_demand_supply.jl (optional visualization module)

How to Run
	Ensure Gurobi is installed and licensed.
	
	Ensure plot_demand_supply.jl is save in the same directory

	Open Julia and run the script