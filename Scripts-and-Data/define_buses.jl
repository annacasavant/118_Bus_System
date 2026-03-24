using PowerSystems
using CSV
using DataFrames

# ============================================================================
# Define Buses: Create the power system foundation
# ============================================================================
# This script creates all bus (node) components and organizes them into regions.
# Buses are the connection points for generators, loads, and transmission lines.

# Create a new power system with 100 MVA as the base power (used for per-unitization)
sys_DA = System(100.0)

# Read bus parameters from CSV file into a DataFrame
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)

# Map CSV column names to variables for easier access
BUS_NUM_COL = "Number"
MIN_VOLT_COL = "Voltage-Min (pu)"
MAX_VOLT_COL = "Voltage-Max (pu)"
BASE_VOLT_COL = "Base Voltage kV"

# Create geographical regions (areas) and add them to the system
# This organizes buses into 3 regions: R1, R2, R3
for i in 1:3
    area = Area("R$i")
    add_component!(sys_DA, area)
end

# Create all buses from the CSV data
# Each bus represents a node in the power system
for row in eachrow(bus_params)
    num = lpad(row[BUS_NUM_COL], 3, '0')  # Format bus number with leading zeros
    min_volt = row[MIN_VOLT_COL]
    max_volt = row[MAX_VOLT_COL]
    base_volt = row[BASE_VOLT_COL]
    
    # Bus 69 is the reference bus (voltage angle reference point)
    # All other buses are PQ (load flow) type buses
    if row[BUS_NUM_COL] == 69
        type = ACBusTypes.REF
    else
        type = ACBusTypes.PQ
    end
    local bus = ACBus(;
        number = row[BUS_NUM_COL],
        name = "bus$num",
        available = true,
        bustype = type,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = min_volt, max = max_volt),
        base_voltage = base_volt,
        area = get_component(Area, sys_DA, row["Area"])
    )
    add_component!(sys_DA, bus)
end
