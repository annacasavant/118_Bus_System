using PowerSystems
using CSV
using DataFrames
using InfrastructureSystems
import InfrastructureSystems as IS
using TimeSeries
using Dates


sys= System(100.0)

## Reading in line, bus and generators data 
line_df = CSV.read("C:/Users/acasavan/GitHub_Repos/118 Bus/branch.csv", DataFrame)
bus_params = CSV.read("C:/Users/acasavan/GitHub_Repos/118 Bus/bus.csv", DataFrame)
gen_params = CSV.read("gen.csv", DataFrame)

## categorizing different types of generators
thermal_gens = DataFrame()
hydro_gens = DataFrame()
solar_gens = DataFrame()
wind_gens = DataFrame()

for row in eachrow(gen_params)
    if row["type"] == "Thermal "
        push!(thermal_gens, row, promote=true)
    elseif row["type"] == "Hydro"
        push!(hydro_gens, row, promote=true)
    elseif row["type"] == "Solar"
        push!(solar_gens, row, promote=true)
    elseif row["type"] == "Wind"
        push!(wind_gens, row, promote=true)
    end
end


## Building buses ===========================================================================================
# Bus 69 is slack, the rest are PQ
buses = []
for i in 1:118
    num = lpad(i, 3, '0')
    min_volt = bus_params[i, "Voltage-Min (pu)"]
    max_volt = bus_params[i, "Voltage-Max (pu)"]
    base_volt = bus_params[i, "Base Voltage kV"]
    if bus_params[i, "Number"] == 69
    bus = ACBus(;
           number = i,
           name = "bus$num",
           bustype = ACBusTypes.REF,
           angle = 0.0,
           magnitude = 1.0,
           voltage_limits = (min = min_volt, max = max_volt),
           base_voltage = base_volt,
       )
    add_component!(sys, bus)
    push!(buses, bus)
    else 
        bus = ACBus(;
        number = i,
        name = "bus$num",
        bustype = ACBusTypes.PQ,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = min_volt, max = max_volt),
        base_voltage = base_volt,
    )
 add_component!(sys, bus)
 push!(buses, bus)  
    end
end

## Building Lines and Transformer2W --------------------------------------------------------------------------
# 
lines = []
for i in 1:186
    num = lpad(i, 3, '0')
    bus_from = parse(Int, line_params[i, "Bus from "][4:6])
    bus_to = parse(Int, line_params[i, "Bus to"][4:6])
    if bus_params[bus_to, "Base Voltage kV"] == bus_params[bus_from, "Base Voltage kV"]
        local line = Line(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = buses[bus_from], to = buses[bus_to]),
            r = line_params[i, 7],
            x = line_params[i, 6],
            b = (from = 0.0, to = 0.0),
            rating = line_params[i, "Max Flow (MW)"]/100,
            angle_limits = (min = 0.0, max = 0.0),
        );
        add_component!(sys, line)
        push!(lines, line)
    else
        local tline = Transformer2W(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = buses[bus_from], to = buses[bus_to]),
            r = line_params[i, 7],
            x = line_params[i, 6],
            primary_shunt = 0.0,
            rating = line_params[i, "Max Flow (MW)"]/100,
        );
        add_component!(sys, tline)
        push!(lines, tline)
    end
end


# Building the Solar Generators
bus_solar = []
solar_DA_gens = []
for i in 1:75
    bus_solar = parse(Int, solar_gens[i, "bus of connection"][4:6])
    solar = RenewableDispatch(;
        name = "solar$i",
        available = true,
        bus = buses[bus_solar],
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.PVe,
        reactive_power_limits = (min = 0.0, max = 0.05),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100.00 # matches system base - assumption
        )
    add_component!(sys, solar)
	#add_time_series!(sys_DA, solar, solar_DA_TS[i])
	#push!(solar_DA_gens, solar)
end


bus_wind = []
wind_DA_gens = []
for i in 1:17
    bus_wind = parse(Int, wind_gens[i, "bus of connection"][4:6])
    wind = RenewableDispatch(;
        name = "wind$i",
        available = true,
        bus = buses[bus_wind],
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.WT,
        reactive_power_limits = (min = 0.0, max = 0.05),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100.00 # matches system base - assumption
        )
    add_component!(sys, wind)
	#add_time_series!(sys_DA, wind, wind_DA_TS[i])
	#push!(wind_DA_gens, wind)
end

## Making RenewableGenerationCost functions
# assume no VOM cost and no curtailment cost 
ren_gens = collect(get_components(RenewableDispatch, sys))
for i in 1:92
    cost_curve = zero(CostCurve)
    cost_ren = RenewableGenerationCost(cost_curve)
    ren_gen = ren_gens[i]
    set_operation_cost!(ren_gen, cost_ren)
end


## Building Hydro Generators ===============================================================================
# Some ramping data was missing 
ramp_up = []
for i in 1:43 
    if ismissing(hydro_gens[i, "Max Ramp Up (MW/min)"])
        push!(ramp_up, 0.0)
    else 
        push!(ramp_up, hydro_gens[i, "Max Ramp Up (MW/min)"])
    end
end
ramp_down = []
for i in 1:43 
    if ismissing(hydro_gens[i, "Max Ramp Down (MW/min)"]) 
        push!(ramp_down, 0.0)
    else 
        push!(ramp_down, hydro_gens[i, "Max Ramp Down (MW/min)"])
    end
end

hydro_DA_RT_gens = []
for i in 1:43
    num = lpad(i, 3, '0')
    bus_hydro = parse(Int, hydro_gens[i, "bus of connection"][4:6])
    hydro = HydroDispatch(;
        name = "hydro$num",
        available = true,
        bus = buses[bus_hydro],
        active_power = 500,
        reactive_power = 0,
        rating = hydro_gens[i, "Max Capacity (MW)"],
        prime_mover_type = PrimeMovers.HA,
        active_power_limits = (min = 0.0, max = hydro_gens[i, "Max Capacity (MW)"]),
        reactive_power_limits = (min = 0.0, max = 0.00),
        ramp_limits = (up = ramp_up[i], down = ramp_down[i]),
        time_limits = (up = hydro_gens[i,"Min Up Time (h)" ], down = hydro_gens[i, "Min Down Time (h)"]),
        base_power = 100.00, # matches system base - assumption
        operation_cost = HydroGenerationCost(nothing)
        )   
    add_component!(sys, hydro)
    #push!(hydro_DA_RT_gens, hydro)
    #add_time_series!(sys_DA, hydro, hydro_DA_RT_TS[i])
end

## Making HydroGenerationCost 
hydrogens = collect(get_components(HydroDispatch, sys))
for i in 1:43 
    cost_curve = LinearCurve(0.0)
    value_curve = CostCurve(cost_curve)
    fixed = 0.0
    cost_hydro = HydroGenerationCost(;variable = value_curve, fixed)
    hydrogen = hydrogens[i]
    set_operation_cost!(hydrogens[i], cost_hydro)
end

## Bilding Thermal Generators ==========================================================================
bus_thermal = []

# Creating prime mover dict
thermal_prime_mover_type = Dict{String, PrimeMovers}(
"OT" => PrimeMovers.OT,
"CC" => PrimeMovers.CC,
"CT" => PrimeMovers.CT,
"HA" => PrimeMovers.HA,
"IC" => PrimeMovers.IC,
#"PVe" => PrimeMovers.Pve,
"WT" => PrimeMovers.WT,
"ST" => PrimeMovers.ST,
)

# Fuel Prices
ng_price = 5.4
coal_price = 1.8
oil_price = 21
bm_price = 2.4
geo_price = 0

# Mapping Fuel Prices and type to type of generators
fuel_prices = []
fuel = []
for i in 1:192
    if thermal_gens[i, "PrimeMoveType"] == "OT"
        push!(fuel_prices, bm_price)
        push!(fuel, ThermalFuels.AG_BIPRODUCT)
    elseif thermal_gens[i, "PrimeMoveType"] == "CC" || startswith(thermal_gens[i, "Generator Name"], "CT NG") || startswith(thermal_gens[i, "Generator Name"], "ICE NG") || startswith(thermal_gens[i, "Generator Name"], "ST NG")
        push!(fuel_prices, ng_price)
        push!(fuel, ThermalFuels.NATURAL_GAS)
    elseif startswith(thermal_gens[i, "Generator Name"], "CT Oil")
        push!(fuel_prices, oil_price)
        push!(fuel, ThermalFuels.DISTILLATE_FUEL_OIL)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Coal")
        push!(fuel_prices, coal_price)
        push!(fuel, ThermalFuels.COAL)
    elseif startswith(thermal_gens[i, "Generator Name"], "Geo")
        push!(fuel_prices, geo_price)
        push!(fuel, ThermalFuels.GEOTHERMAL)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Other 01")
        push!(fuel_prices, oil_price)
        push!(fuel, ThermalFuels.DISTILLATE_FUEL_OIL)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Other 02")
        push!(fuel_prices, ng_price)
        push!(fuel, ThermalFuels.NATURAL_GAS)
    end
end

# parsing rating from gen.csv 
ratings = []
for i in 1:192
    if ismissing(thermal_gens[i, "Rating"]) || thermal_gens[i, "Rating"] == ""
        push!(ratings, 0.0)
    else
        push!(ratings, parse(Float64, thermal_gens[i, "Rating"]))
    end
end

## Creating array of heat rate bands
heat_rate1 = thermal_gens[:, "Heat Rate Inc Band 1 (BTU/kWh)"] ./1000
heat_rate2 = thermal_gens[:, "Heat Rate Inc Band 2 (BTU/kWh)"] ./1000
heat_rate3 = thermal_gens[:, "Heat Rate Inc Band 3 (BTU/kWh)"] ./1000
heat_rate4 = thermal_gens[:, "Heat Rate Inc Band 4 (BTU/kWh)"] ./1000
heat_rate5 = thermal_gens[:, "Heat Rate Inc Band 5 (BTU/kWh)"] ./1000

heat_rates = hcat(
  heat_rate1,
  heat_rate2,
  heat_rate3,
  heat_rate4,
  heat_rate5
)
# Creating array of load points
load_points = hcat(
    thermal_gens[:, "Min Stable Level (MW)"],
    thermal_gens[:, "Load Point Band 1 (MW)"],
    thermal_gens[:, "Load Point Band 2 (MW)"],
    thermal_gens[:, "Load Point Band 3 (MW)"],
    thermal_gens[:, "Load Point Band 4 (MW)"],
    thermal_gens[:, "Load Point Band 5 (MW)"]
)
heat_rate_base = (thermal_gens[:, "Heat Rate Base (MMBTU/hr)"])/1000

# I am assuming that the intervals are defined at the end and beginning by the
# load points, the curve always starts at the minimum stable level and ends at the generators max
# capacity. 

thermal_cost_function = []
for i in 1:192
    max_cap = thermal_gens[i, "Max Capacity (MW)"]
    if ismissing(heat_rates[i,2])
        heat_rate = heat_rate1[i]
        heat_rate_curve = LinearCurve(heat_rate, heat_rate_base[i])
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.00,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0) # no shut down costs in data 
    elseif !ismissing(heat_rates[i,2]) && ismissing(heat_rates[i,3])
        heat_rate = [heat_rate1[i], heat_rate2[i]]
        load_point = [load_points[i,1], load_points[i,2], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0 # no shut down costs in data
        )
elseif !ismissing(heat_rates[i,2]) && !ismissing(heat_rates[i,3]) && ismissing(heat_rates[i,4])
        heat_rate = [heat_rate1[i], heat_rate2[i], heat_rate3[i]]
        load_point = [load_points[i,1], load_points[i,2], load_points[i,3], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0 # no shut down costs in data
        )
    elseif !ismissing(heat_rates[i,2]) && !ismissing(heat_rates[i,3]) && !ismissing(heat_rates[i,4]) && ismissing(heat_rates[i,5])
        heat_rate = [heat_rate1[i], heat_rate2[i], heat_rate3[i], heat_rate4[i]]
        load_point = [load_points[i,1], load_points[i,2], load_points[i,3], load_points[i,4], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0 # no shut down costs in data
        )
    elseif !ismissing(heat_rates[i,2]) && !ismissing(heat_rates[i,3]) && !ismissing(heat_rates[i,4]) && !ismissing(heat_rates[i,5])
        heat_rate = [heat_rate1[i], heat_rate2[i], heat_rate3[i], heat_rate4[i], heat_rate5[i]]
        load_point = [load_points[i,1], load_points[i,2], load_points[i,3], load_points[i,4], load_points[i,5], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0 # no shut down costs in data
        )
end
        push!(thermal_cost_function, cost)
    
end


for i in 1:192
    prime_mover_str = thermal_gens[i, "PrimeMoveType"]
    prime_mover = thermal_prime_mover_type[prime_mover_str]
    bus_thermal = parse(Int, thermal_gens[i, "bus of connection"][4:6])
    max_active_power = thermal_gens[i, "Max Capacity (MW)"]/100
    min_active_power = thermal_gens[i, "Min Stable Level (MW)"]/100
        thermal = ThermalStandard(;
            name = thermal_gens[i, "Generator Name"],
            available = true,
            status = true,
            bus = buses[bus_thermal],
            active_power = 0.0,
            reactive_power = 0.0,
            rating = ratings[i]/100,
            active_power_limits = (min = min_active_power, max = max_active_power),
            reactive_power_limits = nothing,
            ramp_limits = (up = thermal_gens[i, "Max Ramp Up (MW/min)"]/100, down = thermal_gens[i, "Max Ramp Down (MW/min)"]/100),
            operation_cost = ThermalGenerationCost(nothing),
            base_power = 100, 
            time_limits = (up = thermal_gens[i,"Min Up Time (h)" ], down = thermal_gens[i, "Min Down Time (h)"]),
            prime_mover_type = prime_mover,
            fuel = fuel[i],
        )
    add_component!(sys, thermal)
    set_operation_cost!(thermal, thermal_cost_function[i])
end














