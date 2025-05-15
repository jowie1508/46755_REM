# =============================================================================
# Task 1.4: CVaR-Based Wind Bidding Optimization with Varying In-Sample Sizes
# -----------------------------------------------------------------------------
# This script evaluates the effect of in-sample scenario size on profit and risk
# using a CVaR-based formulation under both one- and two-price imbalance schemes.
#
# Type:
#     Linear optimization model with risk aversion (CVaR)
#
# Inputs:
#     - Scenario list with wind, DA price, and system imbalance
#     - In-sample sizes and risk aversion levels
#
# Outputs:
#     - Optimal bidding strategy
#     - Expected revenue and CVaR
#     - Scenario-wise profit distribution
#     - Line plots of CVaR and expected revenue vs. sample size
# =============================================================================

# =============================================================================
# Imports and Initialization
# =============================================================================
from pyomo.environ import *
from pyomo.opt import SolverFactory
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scenarios import main
import os
import random

# Set working directory to script location
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Load data
all_scenarios = main()
random.seed(42)  # For reproducibility
random.shuffle(all_scenarios)

in_sample = all_scenarios[:200]
T = range(24)
S = range(len(in_sample))
max_capacity = 500

# =============================================================================
# Step 1: Create Model Template
# =============================================================================
def create_model_template(scheme, in_sample):
    """
    Create a Pyomo model for wind bidding optimization with CVaR-based risk management.

    This model includes variables for the bidding decision and imbalance handling,
    along with constraints for imbalance definition, decomposition, and the CVaR auxiliary structure.

    Parameters:
        scheme (str): Pricing scheme used, either 'one' or 'two' (one-price or two-price imbalance market).
        in_sample (list): List of scenario dictionaries, each containing 'wind', 'price_da', and 'system' keys.

    Returns:
        ConcreteModel: A Pyomo model instance with sets, variables, and constraints (excluding objective).
    """
    model = ConcreteModel()
    
    # Sets for time periods and scenarios
    model.T = Set(initialize=range(24))
    model.S = Set(initialize=range(len(in_sample)))

    # Decision variable: DA offer quantity per hour (bounded by max capacity)
    model.offer_quantity = Var(model.T, domain=NonNegativeReals, bounds=(0, max_capacity))
    
    # Scenario-dependent imbalance variables: net imbalance = wind - offer
    model.delta = Var(model.S, model.T, domain=Reals)
    
    # Positive and negative parts of imbalance
    model.delta_exc = Var(model.S, model.T, domain=NonNegativeReals)  # Excess (overproduction)
    model.delta_def = Var(model.S, model.T, domain=NonNegativeReals)  # Deficit (underproduction)

    # CVaR components: VaR threshold and auxiliary shortfall variables
    model.VaR = Var(domain=NonNegativeReals)
    model.auxiliary = Var(model.S, domain=NonNegativeReals)

    # Constraint: delta = wind - offer
    def imbalance_def_rule(m, s, t):
        return m.delta[s, t] == in_sample[s]["wind"][t] - m.offer_quantity[t]
    model.ImbalanceDef = Constraint(model.S, model.T, rule=imbalance_def_rule)

    # Constraint: decompose delta into delta_exc - delta_def
    def delta_decomp_rule(m, s, t):
        return m.delta[s, t] == m.delta_exc[s, t] - m.delta_def[s, t]
    model.DeltaDecomp = Constraint(model.S, model.T, rule=delta_decomp_rule)

    # CVaR constraint: auxiliary ≥ VaR - scenario profit (for each scenario and time)
    def auxiliary_rule(m, s, t):
        return m.auxiliary[s] >= m.VaR - sum(
            in_sample[s]["price_da"][t] * m.offer_quantity[t]
            + (
                (0.85 * in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                 - 0.85 * in_sample[s]["price_da"][t] * m.delta_def[s, t]) * in_sample[s]["system"][t]
                if scheme == "one"
                else (0.85 * in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                      - in_sample[s]["price_da"][t] * m.delta_def[s, t]) * in_sample[s]["system"][t]
            )
            + (
                (1.25 * in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                 - 1.25 * in_sample[s]["price_da"][t] * m.delta_def[s, t]) * (1 - in_sample[s]["system"][t])
                if scheme == "one"
                else (in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                      - 1.25 * in_sample[s]["price_da"][t] * m.delta_def[s, t]) * (1 - in_sample[s]["system"][t])
            )
            for t in range(24)
        )
    model.Auxiliary = Constraint(model.S, model.T, rule=auxiliary_rule)

    return model

# =============================================================================
# Step 2: Solve Model and Extract Results
# =============================================================================
def solve_and_extract(scheme: str, beta, in_sample, solver, return_only=False, alpha=0.90):
    """
    Solve the CVaR-based wind bidding optimization model and extract key metrics.

    This function sets up the objective using a combination of expected profit and 
    Conditional Value-at-Risk (CVaR), solves the model using the specified solver, 
    and returns hourly bids, expected revenue, CVaR, and per-scenario profit data.

    Parameters:
        scheme (str): 'one' or 'two' for one-price or two-price imbalance pricing.
        beta (float): Risk aversion level (0 = risk-neutral, 1 = fully risk-averse).
        in_sample (list): List of scenario dictionaries containing wind, price_da, and system flags.
        solver: A Pyomo solver object (e.g., SolverFactory('gurobi')).
        return_only (bool): If True, return only optimal bids and expected profit.
        alpha (float): CVaR quantile (default is 0.90 for 90% confidence).

    Returns:
        pd.DataFrame: Hourly bid and expected revenue data.
        float: Expected revenue over in-sample scenarios.
        float: Conditional Value-at-Risk (CVaR) value.
        list: Profit per scenario.
    """
    # Build model using in-sample data and pricing scheme
    model = create_model_template(scheme, in_sample)

    # Define the CVaR-based objective function: weighted sum of expected profit and downside risk
    def revenue(m):
        return (1 - beta) * ((1 / len(in_sample)) * sum(
            sum(
                in_sample[s]["price_da"][t] * m.offer_quantity[t]
                + (
                    (0.85 * in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                     - 0.85 * in_sample[s]["price_da"][t] * m.delta_def[s, t]) * in_sample[s]["system"][t]
                    if scheme == "one"
                    else (0.85 * in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                          - in_sample[s]["price_da"][t] * m.delta_def[s, t]) * in_sample[s]["system"][t]
                )
                + (
                    (1.25 * in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                     - 1.25 * in_sample[s]["price_da"][t] * m.delta_def[s, t]) * (1 - in_sample[s]["system"][t])
                    if scheme == "one"
                    else (in_sample[s]["price_da"][t] * m.delta_exc[s, t]
                          - 1.25 * in_sample[s]["price_da"][t] * m.delta_def[s, t]) * (1 - in_sample[s]["system"][t])
                )
                for s in range(len(in_sample))
            ) for t in range(24)
        )) + beta * (m.VaR - 1 / (1 - alpha) * sum(
            (1 / len(in_sample)) * m.auxiliary[s] for s in range(len(in_sample))
        ))

    # Set objective in model
    model.ExpectedRevenue = Objective(rule=revenue, sense=maximize)

    # Solve the model
    solver = SolverFactory('gurobi')  
    result = solver.solve(model, tee=False)

    # If solved successfully, extract offer quantities and expected profit
    if (result.solver.status == SolverStatus.ok) and (result.solver.termination_condition == TerminationCondition.optimal):
        offer_quantities = [value(model.offer_quantity[t]) for t in range(24)]
        expected_profit = value(model.ExpectedRevenue)

        # Option to return only strategy and expected profit (e.g. for cross-validation)
        if return_only:
            return offer_quantities, expected_profit

    # Collect hourly bidding and revenue data
    data = []
    for t in range(24):
        bid = offer_quantities[t]
        total_revenue = 0
        for s in range(len(in_sample)):
            p_da = in_sample[s]["price_da"][t]
            delta_up = value(model.delta_exc[s, t])
            delta_down = value(model.delta_def[s, t])
            system_flag = in_sample[s]["system"][t]

            # Revenue logic depends on scheme and system direction
            if scheme == "one":
                revenue = (
                    p_da * bid
                    + 0.85 * p_da * delta_up
                    - 0.85 * p_da * delta_down if system_flag == 1
                    else 1.25 * p_da * delta_up - 1.25 * p_da * delta_down
                )
            else:
                revenue = (
                    p_da * bid
                    + 0.85 * p_da * delta_up
                    - p_da * delta_down if system_flag == 1
                    else p_da * delta_up - 1.25 * p_da * delta_down
                )
            total_revenue += revenue

        avg_revenue = total_revenue / len(in_sample)

        # Store for plotting
        data.append({
            "hour": t,
            "bid_MW": bid,
            "expected_revenue_€": avg_revenue,
            "scheme": "One-Price" if scheme == "one" else "Two-Price"
        })

    # Compute CVaR from auxiliary variables
    cvar = value(model.VaR) - (1 / (1 - alpha)) * sum((1 / len(in_sample)) *
        value(model.auxiliary[s]) for s in range(len(in_sample))
    )

    # Compute expected revenue based on actual model output (not objective value)
    expected_revenue = (1 / len(in_sample)) * sum(
        sum(
            in_sample[s]["price_da"][t] * value(model.offer_quantity[t])
            + (
                (0.85 * in_sample[s]["price_da"][t] * value(model.delta_exc[s, t])
                 - 0.85 * in_sample[s]["price_da"][t] * value(model.delta_def[s, t])) * in_sample[s]["system"][t]
                if scheme == "one"
                else (0.85 * in_sample[s]["price_da"][t] * value(model.delta_exc[s, t])
                      - in_sample[s]["price_da"][t] * value(model.delta_def[s, t])) * in_sample[s]["system"][t]
            )
            + (
                (1.25 * in_sample[s]["price_da"][t] * value(model.delta_exc[s, t])
                 - 1.25 * in_sample[s]["price_da"][t] * value(model.delta_def[s, t])) * (1 - in_sample[s]["system"][t])
                if scheme == "one"
                else (in_sample[s]["price_da"][t] * value(model.delta_exc[s, t])
                      - 1.25 * in_sample[s]["price_da"][t] * value(model.delta_def[s, t])) * (1 - in_sample[s]["system"][t])
            )
            for t in range(24)
        ) for s in range(len(in_sample))
    )

    print(f"Expected Revenue: {expected_revenue:.2f} €, CVaR: {cvar:.2f} €")

    # Scenario-wise profit computation
    profits_per_scenario = []
    for s in range(len(in_sample)):
        profit_s = 0
        for t in range(24):
            p_da = in_sample[s]["price_da"][t]
            delta_up = value(model.delta_exc[s, t])
            delta_down = value(model.delta_def[s, t])
            bid = value(model.offer_quantity[t])
            system_flag = in_sample[s]["system"][t]

            if scheme == "one":
                if system_flag == 1:
                    profit_s += p_da * bid + 0.85 * p_da * delta_up - 0.85 * p_da * delta_down
                else:
                    profit_s += p_da * bid + 1.25 * p_da * delta_up - 1.25 * p_da * delta_down
            else:
                if system_flag == 1:
                    profit_s += p_da * bid + 0.85 * p_da * delta_up - p_da * delta_down
                else:
                    profit_s += p_da * bid + p_da * delta_up - 1.25 * p_da * delta_down

        profits_per_scenario.append(profit_s)

    return pd.DataFrame(data), expected_revenue, cvar, profits_per_scenario


# =============================================================================
# Step 3: plot and compare results
# =============================================================================
def plot_bid_and_revenue_comparison(df_combined):
    """
    Plot bidding strategy and expected revenue for one- and two-price schemes.

    This function generates a bar plot showing hourly bid quantities and overlays
    a line plot of expected revenue. Each pricing scheme is shown using a different
    color for comparison.

    Parameters:
        df_combined (pd.DataFrame): DataFrame with columns:
            - hour
            - bid_MW
            - expected_revenue_€
            - scheme (either 'One-Price' or 'Two-Price')
    """
    sns.set(style="whitegrid")
    fig, ax1 = plt.subplots(figsize=(12, 6))

    # Bar plot: hourly bidding quantities
    sns.barplot(data=df_combined, x="hour", y="bid_MW", hue="scheme", ax=ax1)
    ax1.set_ylabel("Bid (MW)")
    ax1.set_xlabel("Hour of Day")
    ax1.tick_params(axis='y')

    # Line plot: expected revenue per hour
    ax2 = ax1.twinx()
    sns.lineplot(data=df_combined, x="hour", y="expected_revenue_€",
                 hue="scheme", style="scheme", markers=True, dashes=False, ax=ax2)
    ax2.set_ylabel("Expected Revenue (€)")
    ax2.tick_params(axis='y')

    # Separate legends
    ax1.legend(loc='upper left')
    ax2.legend(loc='upper right')
    plt.tight_layout()
    plt.show()

# Run everything
solver = SolverFactory("gurobi")




# Define in-sample sizes and beta values
scenario_sizes = [100,200,400,800,1600] #Adjust to desired sizes
betas = [0.5] #adjust to desired betas

results = []

# Run for each scenario size and beta
for size in scenario_sizes:
    sample = random.sample(all_scenarios, size)
    for beta in betas:
        print(f"\nSize: {size}, Beta: {beta:.2f}")
        _, exp_rev_one, cvar_one, _ = solve_and_extract("one", beta, sample, solver)
        _, exp_rev_two, cvar_two, _ = solve_and_extract("two", beta, sample, solver)

        results.append({
            "sample_size": size,
            "beta": beta,
            "expected_profit_one": exp_rev_one,
            "cvar_one": cvar_one,
            "expected_profit_two": exp_rev_two,
            "cvar_two": cvar_two,
        })

# Convert results to DataFrame
df = pd.DataFrame(results)

# Filter for beta = 0.5 and scheme = "Two-Price"
df_filtered = df[df["beta"] == 0.5]

# Create simplified DataFrame for Two-Price only
df_two_price = pd.DataFrame({
    "sample_size": df_filtered["sample_size"],
    "Expected Profit (€)": df_filtered["expected_profit_one"],
    "CVaR (€)": df_filtered["cvar_one"]
})

# Sort by sample size just in case
df_two_price = df_two_price.sort_values("sample_size")

# Filter for beta = 0.5
df_filtered = df[df["beta"] == 0.5]

# Create DataFrame for Two-Price only
df_two_price = pd.DataFrame({
    "sample_size": df_filtered["sample_size"],
    "Expected Profit (€)": df_filtered["expected_profit_one"],
    "CVaR (€)": df_filtered["cvar_two"]
}).sort_values("sample_size")

# --- Plot Expected Profit ---
plt.figure(figsize=(8, 5))
sns.lineplot(data=df_two_price, x="sample_size", y="Expected Profit (€)",
             marker="o", linewidth=2, color="steelblue")
plt.title("Expected Profit vs In-Sample Size (Two-Price, β = 0.5)", fontsize=16)
plt.xlabel("In-Sample Scenario Size", fontsize=16)
plt.ylabel("Expected Profit (€)", fontsize=16)
plt.xticks(fontsize=14)
plt.yticks(fontsize=14)
plt.grid(True)
plt.tight_layout()
#plt.show()  #Uncomment to show the plot

# --- Plot CVaR ---
plt.figure(figsize=(8, 5))
sns.lineplot(data=df_two_price, x="sample_size", y="CVaR (€)",
             marker="o", linewidth=2, color="darkred")
plt.title("CVaR vs In-Sample Size (Two-Price, β = 0.5)", fontsize=16)
plt.xlabel("In-Sample Scenario Size", fontsize=16)
plt.ylabel("CVaR (€)", fontsize=16)
plt.xticks(fontsize=14)
plt.yticks(fontsize=14)
plt.grid(True)
plt.tight_layout()
#plt.show() Uncomment to show the plot




