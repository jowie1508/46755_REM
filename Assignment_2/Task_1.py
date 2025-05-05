from pyomo.environ import *
from pyomo.opt import SolverFactory
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scenarios import main
import os

# Set working directory to script location
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Load data
all_scenarios = main()
in_sample = all_scenarios[:200]
T = range(24)
S = range(len(in_sample))
max_capacity = 500


# Step 1: Create base model template (without objective)
def create_model_template(in_sample):
    model = ConcreteModel()
    model.T = Set(initialize=range(24))
    model.S = Set(initialize=range(len(in_sample)))

    model.offer_quantity = Var(model.T, domain=NonNegativeReals, bounds=(0, max_capacity))
    model.delta = Var(model.S, model.T, domain=Reals)
    model.delta_exc = Var(model.S, model.T, domain=NonNegativeReals)
    model.delta_def = Var(model.S, model.T, domain=NonNegativeReals)

    def imbalance_def_rule(m, s, t):
        return m.delta[s, t] == in_sample[s]["wind"][t] - m.offer_quantity[t]
    model.ImbalanceDef = Constraint(model.S, model.T, rule=imbalance_def_rule)

    def delta_decomp_rule(m, s, t):
        return m.delta[s, t] == m.delta_exc[s, t] - m.delta_def[s, t]
    model.DeltaDecomp = Constraint(model.S, model.T, rule=delta_decomp_rule)

    return model


# Step 2: Solve and extract results
def solve_and_extract(scheme: str, in_sample, solver):
    model = create_model_template(in_sample)

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
    # Solve the model
    solver = SolverFactory('gurobi')  
    result = solver.solve(model, tee=True)

    ## Output 
    if (result.solver.status == SolverStatus.ok) and (result.solver.termination_condition == TerminationCondition.optimal):
        print("\nOptimal Offer Quantities:")
        for t in T:
            print(f"Hour {t}: Offer {value(model.offer_quantity[t]):.2f} MW")
        print(f"\nExpected Profit: {value(model.ExpectedRevenue):.2f} €")
    else:
        print("Optimization failed.")

    # Extract hourly bid & revenue
    data = []
    for t in range(24):
        bid = value(model.offer_quantity[t])
        total_revenue = 0
        for s in range(len(in_sample)):
            p_da = in_sample[s]["price_da"][t]
            delta_up = value(model.delta_exc[s, t])
            delta_down = value(model.delta_def[s, t])
            system_flag = in_sample[s]["system"][t]

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
        data.append({
            "hour": t,
            "bid_MW": bid,
            "expected_revenue_€": avg_revenue,
            "scheme": "One-Price" if scheme == "one" else "Two-Price"
        })

    return pd.DataFrame(data)


# Step 3: Plot comparison
def plot_bid_and_revenue_comparison(df_combined):
    sns.set(style="whitegrid")
    fig, ax1 = plt.subplots(figsize=(12, 6))

    # Barplot: bids
    sns.barplot(data=df_combined, x="hour", y="bid_MW", hue="scheme", ax=ax1)
    ax1.set_ylabel("Bid (MW)")
    ax1.set_xlabel("Hour of Day")
    ax1.tick_params(axis='y')

    # Lineplot: revenue
    ax2 = ax1.twinx()
    sns.lineplot(data=df_combined, x="hour", y="expected_revenue_€",
                 hue="scheme", style="scheme", markers=True, dashes=False, ax=ax2)
    ax2.set_ylabel("Expected Revenue (€)")
    ax2.tick_params(axis='y')

    ax1.legend(loc='upper left')
    ax2.legend(loc='upper right')
    plt.tight_layout()
    plt.show()


# Run everything
solver = SolverFactory("gurobi")

df_one = solve_and_extract("one", in_sample, solver)
df_two = solve_and_extract("two", in_sample, solver)
df_combined = pd.concat([df_one, df_two], ignore_index=True)

plot_bid_and_revenue_comparison(df_combined)
