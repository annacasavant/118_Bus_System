using PowerSystems
using CSV
using DataFrames

# defining DA and RT systems
# reading in bus data to a dataframe

sys_DA= System(100.0) #assuming base power 100MVA per-unitization
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)

# defining column names as variables
BUS_NUM_COL = "Number"
MIN_VOLT_COL = "Voltage-Min (pu)"
MAX_VOLT_COL = "Voltage-Max (pu)"
BASE_VOLT_COL = "Base Voltage kV"

# Creating regions and adding them to system

for i in 1:3
    area = Area("R$i")
    add_component!(sys_DA, area)
end

# Defining all the buses 

for row in eachrow(bus_params)
    num = lpad(row[BUS_NUM_COL], 3, '0')
    min_volt = row[MIN_VOLT_COL]
    max_volt = row[MAX_VOLT_COL]
    base_volt = row[BASE_VOLT_COL]
    if row[BUS_NUM_COL] == 69
        type = ACBusTypes.REF
    else
        type = ACBusTypes.PQ
    end
    local bus = ACBus(;
        number = row[BUS_NUM_COL],
        name = "bus$num",
        bustype = type,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = min_volt, max = max_volt),
        base_voltage = base_volt,
        area = get_component(Area, sys_DA, row["Area"])
    )
    add_component!(sys_DA, bus)
end
