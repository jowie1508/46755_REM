import numpy as np
import pandas as pd

# Set working directory to the location of this script
import os

# Set the working directory to the script's directory
os.chdir(os.path.dirname(os.path.abspath(__file__)))


def generate_power_scenarios(num_scenarios, p_deficit=0.5, seed=None):
    """
    Generate binary 24-hour power system condition scenarios.
    
    Parameters:
    - num_scenarios (int): Number of 24-hour scenarios to generate.
    - p_deficit (float): Probability of power deficit (1) for each hour (default: 0.5).
    - seed (int, optional): Random seed for reproducibility.
    
    Returns:
    - np.ndarray: A (num_scenarios x 24) array of binary values (0 = excess, 1 = deficit).
    """
    if seed is not None:
        np.random.seed(seed)
    
    scenarios = np.random.binomial(1, p_deficit, size=(num_scenarios, 24))
    return scenarios


def read_data(filename, sheet_name=0):
    # Excel-Datei einlesen
    df = pd.read_excel(filename, sheet_name=sheet_name)
    
    # Entferne die erste Spalte (Zeitdaten)
    df = df.iloc[:, 1:]
    
    # Entferne die erste Zeile (Spaltennamen)
    data_only = df.values.tolist()
    
    # Jetzt Daten transponieren, um spaltenweise Listen zu bekommen
    columns_as_lists = list(map(list, zip(*data_only)))
    
    return columns_as_lists

def create_combined_scenarios(price_data_da, wind_data, power_scenarios, wind_capacity=500):
    """
    Combine price, wind, and power scenarios into a full scenario tree.
    
    Parameters:
    - price_data (list of lists): 20 price scenarios, each list = 24 hourly values
    - wind_data (list of lists): 20 wind scenarios, each list = 24 hourly values
    - power_scenarios (np.ndarray): 4 power scenarios, shape (4 x 24)
    
    Returns:
    - list of dicts: 1600 scenarios, each with keys 'price', 'wind', 'power'
    """
    scenarios = []


    for i, price_da in enumerate(price_data_da):
        for j, wind in enumerate(wind_data):
            for k, power in enumerate(power_scenarios):
                power_list = power.tolist()  # Numpy -> Python list
                
                # Create balancing prices
                balancing_prices = [
                    price_da[t] * 0.85 if power_list[t] == 1 else price_da[t] * 1.25
                    for t in range(24)
                ]

                scenario = {
                    'wind': [w * wind_capacity for w in wind],  # Scale wind data to MW
                    'price_da': price_da,
                    'price_bal': balancing_prices,
                    'system': power_list,   

                }
                scenarios.append(scenario)
    
    return scenarios

def main():
    # Load input data (each as list of 20 columns, each column = 24 hours)
    wind_data = read_data("wind_data.xlsx")       # Expected: 20 wind scenarios
    price_data = read_data("price_data_zeroed.xlsx")     # Expected: 20 price scenarios

    
    # Generate 4 power scenarios (binary 0/1 per hour)
    power_scenarios = generate_power_scenarios(4, p_deficit=0.5, seed=42)

    # Combine into 1600 total scenarios: 20 * 20 * 4
    all_scenarios = create_combined_scenarios(price_data, wind_data, power_scenarios)

    print(f"Generated {len(all_scenarios)} combined scenarios.")  # Should be 1600
    return all_scenarios


# Call main function to execute the script
if __name__ == "__main__":
    all_scenarios = main()

    # Print first scenario for verification
    print("First scenario:")
    print(all_scenarios[0])
