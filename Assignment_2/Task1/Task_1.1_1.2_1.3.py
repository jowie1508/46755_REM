# =============================================================================
# Task 1.1 and 1.2: Wind Bidding Optimization Under One-Price and Two-Price imbalance
# -----------------------------------------------------------------------------
# This script optimizes 24-hour wind power bidding under one-price and
# two-price imbalance pricing using Pyomo and Gurobi.
#
# Type:
#     Linear optimization model (profit maximization)
#
# Inputs:
#     - Scenario list with hourly wind, DA price, and system imbalance
#     - Max bidding capacity (500 MW)
#
# Outputs:
#     - Optimal hourly offer quantities (MW)
#     - Expected revenue under each pricing scheme
#     - Comparison plot of bid and revenue profiles
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
import time

# Set working directory to this script's folder
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Load and shuffle all scenarios
all_scenarios = main()  # Load scenarios from the scenarios module
random.seed(42) # Set seed for reproducibility
random.shuffle(all_scenarios)

# Select 200 in-sample scenarios for optimization
in_sample = all_scenarios[:200] 
T = range(24)
S = range(len(in_sample))
max_capacity = 500  # Max bidding quantity in MW

# =============================================================================
# Step 1: Create Model Template (No Objective Yet)
# =============================================================================
def create_model_template(in_sample):
    """
    Build Pyomo model structure with variables and constraints,
    excluding the objective function.

    Parameters:
    - in_sample (list): Scenario data with wind, price_da, system flags

    Returns:
    - ConcreteModel: Pyomo optimization model
    """
    model = ConcreteModel()
    model.T = Set(initialize=range(24))
    model.S = Set(initialize=range(len(in_sample)))

    # Decision variables
    model.offer_quantity = Var(model.T, domain=NonNegativeReals, bounds=(0, max_capacity))
    model.delta = Var(model.S, model.T, domain=Reals)
    model.delta_exc = Var(model.S, model.T, domain=NonNegativeReals)
    model.delta_def = Var(model.S, model.T, domain=NonNegativeReals)

    # Constraint: Imbalance definition (wind - offer)
    def imbalance_def_rule(m, s, t):
        return m.delta[s, t] == in_sample[s]["wind"][t] - m.offer_quantity[t]
    model.ImbalanceDef = Constraint(model.S, model.T, rule=imbalance_def_rule)

    # Constraint: Decompose delta into up/down parts
    def delta_decomp_rule(m, s, t):
        return m.delta[s, t] == m.delta_exc[s, t] - m.delta_def[s, t]
    model.DeltaDecomp = Constraint(model.S, model.T, rule=delta_decomp_rule)

    return model

# =============================================================================
# Step 2: Solve Model and Extract Results
# =============================================================================
def solve_and_extract(scheme: str, in_sample, solver, return_only=False):
    """
    Solve wind bidding optimization for a given pricing scheme.

    Parameters:
    - scheme (str): 'one' or 'two' price imbalance scheme
    - in_sample (list): Scenario set
    - solver: Pyomo solver object
    - return_only (bool): If True, return strategy only

    Returns:
    - DataFrame or (list, float): Hourly bid and revenue info, or strategy
    """
    model = create_model_template(in_sample)

    # Define expected revenue objective
    def revenue(m):
        return (1 / len(in_sample)) * sum(
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
        )

    model.ExpectedRevenue = Objective(rule=revenue, sense=maximize)

    # Solve using Gurobi
    solver = SolverFactory('gurobi')  
    start_time = time.time()
    result = solver.solve(model, tee=True)
    solve_time = time.time() - start_time
    print(f"\nSolving time for {scheme}-price scheme: {solve_time:.2f} seconds")

    if (result.solver.status == SolverStatus.ok) and (result.solver.termination_condition == TerminationCondition.optimal):
        offer_quantities = [value(model.offer_quantity[t]) for t in range(24)]
        expected_profit = value(model.ExpectedRevenue)

        if return_only:
            return offer_quantities, expected_profit
        else:
            print("\nOptimal Offer Quantities:")
            for t in T:
                print(f"Hour {t}: Offer {value(model.offer_quantity[t]):.2f} MW")
            print(f"\nExpected Profit: {expected_profit:.2f} €")

    # Collect hourly bidding and revenue info
    data = []
    for t in range(24):
        bid = offer_quantities[t]
        total_revenue = 0
        for s in range(len(in_sample)):
            p_da = in_sample[s]["price_da"][t]
            delta_up = value(model.delta_exc[s, t])
            delta_down = value(model.delta_def[s, t])
            system_flag = in_sample[s]["system"][t]

            if scheme == "one":
                revenue = (
                    p_da * bid + 0.85 * p_da * delta_up - 0.85 * p_da * delta_down
                    if system_flag == 1 else 1.25 * p_da * delta_up - 1.25 * p_da * delta_down
                )
            else:
                revenue = (
                    p_da * bid + 0.85 * p_da * delta_up - p_da * delta_down
                    if system_flag == 1 else p_da * delta_up - 1.25 * p_da * delta_down
                )
            total_revenue += revenue

        avg_revenue = total_revenue / len(in_sample)
        data.append({
            "hour": t,
            "bid_MW": bid,
            "expected_revenue_€": avg_revenue,
            "scheme": "One-Price" if scheme == "one" else "Two-Price"
        })

    return pd.DataFrame(data)

# =============================================================================
# Step 3: Plot Bidding and Revenue Comparison
# =============================================================================
def plot_bid_and_revenue_comparison(df_combined):
    """
    Plot bar chart of bids and line plot of expected revenues per hour
    for both pricing schemes.

    Parameters:
    - df_combined (DataFrame): Combined results from both schemes
    """
    sns.set(style="whitegrid")
    fig, ax1 = plt.subplots(figsize=(12, 6))

    # Barplot for bids
    sns.barplot(data=df_combined, x="hour", y="bid_MW", hue="scheme", ax=ax1)
    ax1.set_ylabel("Bid (MW)")
    ax1.set_xlabel("Hour of Day")
    ax1.tick_params(axis='y')

    # Lineplot for expected revenue
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

# =============================================================================
# Run Optimization and Visualization
# =============================================================================
solver = SolverFactory("gurobi")

# Run optimization for both schemes
df_one = solve_and_extract("one", in_sample, solver)
df_two = solve_and_extract("two", in_sample, solver)

# Combine results and plot
df_combined = pd.concat([df_one, df_two], ignore_index=True)
plot_bid_and_revenue_comparison(df_combined)


# =============================================================================
# Task 1.3: Cross-Validation for Generalization Gap Analysis
# -----------------------------------------------------------------------------
# This script evaluates the generalization performance of a risk-averse offering
# strategy by comparing in-sample and out-of-sample profits for various sizes
# of in-sample scenario sets under one- or two-price market schemes.
# =============================================================================

def evaluate_profit(offer_quantities, scenarios, scheme):
    """
    Evaluate the average profit of a fixed bidding strategy over a set of scenarios.

    This function simulates the financial outcome of a predefined hourly bidding strategy
    (offer quantities) applied to a set of scenarios, without re-optimizing.

    Parameters:
        offer_quantities (list of float): List of 24 bid values for each hour.
        scenarios (list of dict): Scenario data containing 'wind', 'price_da', and 'system' keys.
        scheme (str): Market scheme, either 'one' or 'two' for one-price or two-price imbalance.

    Returns:
        float: Average profit over all scenarios.
    """
    total_profit = 0

    for s in scenarios:
        scenario_profit = 0
        for t in range(24):
            bid = offer_quantities[t]
            wind = s["wind"][t]
            p_da = s["price_da"][t]
            system_flag = s["system"][t]

            imbalance = wind - bid

            if imbalance >= 0:
                # Excess wind
                if scheme == "one":
                    revenue = p_da * bid + (0.85 if system_flag == 1 else 1.25) * p_da * imbalance
                else:
                    revenue = p_da * bid + (0.85 if system_flag == 1 else 1.00) * p_da * imbalance
            else:
                # Deficit
                deficit = -imbalance
                if scheme == "one":
                    revenue = p_da * bid - (0.85 if system_flag == 1 else 1.25) * p_da * deficit
                else:
                    revenue = p_da * bid - (1.00 if system_flag == 1 else 1.25) * p_da * deficit

            scenario_profit += revenue
        total_profit += scenario_profit

    return total_profit / len(scenarios)


def run_cross_validation_for_sizes(all_scenarios, in_sample_sizes, scheme="one", solver=None):
    """
    Perform k-fold cross-validation for different in-sample scenario sizes.

    For each size, the function creates k folds, trains the model on one fold,
    evaluates it on the remaining folds, and computes the generalization gap
    between in-sample and out-of-sample profits.

    Parameters:
        all_scenarios (list): Complete scenario dataset.
        in_sample_sizes (list): List of in-sample scenario sizes to test.
        scheme (str): Market imbalance pricing scheme ('one' or 'two').
        solver (SolverFactory): Pyomo solver used to solve the optimization model.

    Returns:
        pd.DataFrame: Summary of average in-sample profit, out-of-sample profit,
                      and the generalization gap for each in-sample size.
    """
    results = []

    for in_sample_size in in_sample_sizes:
        print("\n" + "=" * 40)
        print(f"Cross-Validation for In-Sample Size: {in_sample_size}")
        print("=" * 40)

        num_folds = len(all_scenarios) // in_sample_size
        scenarios_copy = all_scenarios[:] # Make a copy to avoid modifying the original list
        random.seed(42) # Set seed for reproducibility
        random.shuffle(scenarios_copy) # Shuffle the scenarios

        # Split data into folds of the given in-sample size
        folds = [
            scenarios_copy[i * in_sample_size : (i + 1) * in_sample_size]
            for i in range(num_folds)
        ]
        # Initialize lists to store profits
        in_sample_profits = []
        out_sample_profits = []

        # Perform k-fold cross-validation
        for i in range(num_folds):
            print(f"\n  Running Fold {i+1}/{num_folds}...")

            in_sample = folds[i]
            out_sample = [s for j, fold in enumerate(folds) if j != i for s in fold]

            # Train on one fold, evaluate on the rest
            offer_quantities, in_profit = solve_and_extract(scheme, in_sample, solver, return_only=True)
            out_profit = evaluate_profit(offer_quantities, out_sample, scheme)

            in_sample_profits.append(in_profit)
            out_sample_profits.append(out_profit)

            print(f"    In-Sample Profit: {in_profit:.2f} €, Out-of-Sample Profit: {out_profit:.2f} €")

        # Compute average values and generalization gap
        avg_in = np.mean(in_sample_profits)
        avg_out = np.mean(out_sample_profits)
        gap = avg_in - avg_out

        print(f"\n   Summary for In-Sample Size {in_sample_size}")
        print(f"     Avg In-Sample Profit: {avg_in:.2f} €")
        print(f"     Avg Out-Sample Profit: {avg_out:.2f} €")
        print(f"     Generalization Gap: {gap:.2f} €")

        results.append({
            "In-Sample Size": in_sample_size,
            "Avg In-Sample Profit": avg_in,
            "Avg Out-Sample Profit": avg_out,
            "Generalization Gap": gap
        })

    return pd.DataFrame(results)


# =============================================================================
# Execute Cross-Validation and Plot
# =============================================================================

in_sample_sizes = [100, 200, 400, 800]  # Scenario sizes to test
scheme = "two"  # Pricing scheme to evaluate, can be "one" or "two"

# Run cross-validation
results_df = run_cross_validation_for_sizes(all_scenarios, in_sample_sizes, scheme, solver)

# Display results
print("\n=== All Results ===")
print(results_df)

# Plot generalization gap
plt.figure(figsize=(8, 4.5))
plt.plot(results_df["In-Sample Size"], results_df["Generalization Gap"], marker='d', color='crimson')
plt.xlabel("In-Sample Size")
plt.ylabel("Generalization Gap (€)")
plt.grid(True)
plt.tight_layout()
# plt.show() # Uncomment to display the plot
