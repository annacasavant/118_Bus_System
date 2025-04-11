using PowerSystems
using CSV
using DataFrames

#=
This script establishes the base system, labeled sys_DA, and creates and adds
the buses and regions to the system. These systems, sys_DA and sys_RT, are
exactly the same until time series are introduced. Thus, we build one system
and create sys_RT via deepcopy once sys_DA and sys_RT diverge. Naming buses now
with convention "bus001" because other files use this naming convention.
Setting angle equal to 0.0 in the ACBus constructor because its missing from
our data.
=#

# defining base system

system_base_power = 100.0 # assuming base power 100MVA per-unitization
sys_DA = System(system_base_power)

# reading in bus data to a dataframe and defining column names as variables

bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)
    
BUS_NUM = "Number"
MIN_VOLT = "Voltage-Min (pu)"
MAX_VOLT = "Voltage-Max (pu)"
BASE_VOLT = "Base Voltage kV"
REGION = "Area"

# Creating regions and buses, and adding them to system

regions = unique(bus_params[:, REGION])

for reg in regions
    area = Area(reg)
    add_component!(sys_DA, area)
end

for row in eachrow(bus_params)
    num = lpad(row[BUS_NUM], 3, '0')
    if row[BUS_NUM] == 69
        type = ACBusTypes.REF
    else
        type = ACBusTypes.PQ
    end
    local bus = ACBus(;
        number = row[BUS_NUM],
        name = "bus$(num)",
        bustype = type,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = row[MIN_VOLT], max = row[MAX_VOLT]),
        base_voltage = row[BASE_VOLT],
        area = get_component(Area, sys_DA, row[REGION])
    )
    add_component!(sys_DA, bus)
end
