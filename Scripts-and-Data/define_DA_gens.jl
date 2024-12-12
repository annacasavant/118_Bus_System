#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

#definiting all the generators and adding them to appropriate buses

#parsing all ThermalStandard gens 

gen_params = CSV.read("Scripts-and-Data/gen.csv", DataFrame)
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

#building the solar gens
solar_DA_gens = []
for i in 1:75
	num = lpad(i, 3, '0')
    local bus_solar = parse(Int, solar_gens[i, "bus of connection"][4:6])
    local solar = RenewableDispatch(;
        name = "solar$num",
        available = true,
        bus = buses[bus_solar],
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.PVe,
        reactive_power_limits = (min = 0.0, max = 0.05),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 0.00
        )
    add_component!(system, solar)
	add_time_series!(system, solar, solar_DA_TS[i])
	push!(solar_DA_gens, solar)
end

#building the wind gens
wind_DA_gens = []
for i in 1:17
	num = lpad(i, 3, '0')
    local bus_wind = parse(Int, wind_gens[i, "bus of connection"][4:6])
    local wind = RenewableDispatch(;
        name = "wind$num",
        available = true,
        bus = buses[bus_wind],
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.WT,
        reactive_power_limits = (min = 0.0, max = 0.05),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 0.00
        )
    add_component!(system, wind)
	add_time_series!(system, wind, wind_DA_TS[i])
	push!(wind_DA_gens, wind)
end

# building hydro
hydro_DA_RT_gens = []
for i in 1:43
	local num = lpad(i, 3, '0')
    local bus_hydro = parse(Int, hydro_gens[i, "bus of connection"][4:6])
    local hydro = HydroDispatch(;
        name = "hydro$num",
        available = true,
        bus = buses[bus_hydro],
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.HA,
        active_power_limits = (min = 0.0, max = 0.05),
        reactive_power_limits = (min = 0.0, max = 0.05),
        ramp_limits = (up = hydro_gens[i, "Max Ramp Up (MW/min)"], down = hydro_gens[i, "Max Ramp Down (MW/min)"]),
        time_limits = (up = hydro_gens[i,"Min Up Time (h)" ], down = hydro_gens[i, "Min Down Time (h)"]),
        base_power = 0.00,
        operation_cost = HydroGenerationCost(nothing)
        )
    add_component!(system, hydro)
	push!(hydro_DA_RT_gens, hydro)
	add_time_series!(system, hydro, hydro_DA_RT_TS[i])
end

# building thermal gens

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

# parsing rating from gen.csv
ratings = []

for i in 1:192
	if ismissing(thermal_gens[i, "Rating"]) || thermal_gens[i, "Rating"] == ""
        push!(ratings, 0.0)
    else
        push!(ratings, parse(Float64, thermal_gens[i, "Rating"]))
    end
    prime_mover_str = thermal_gens[i, "PrimeMoveType"]
    prime_mover = thermal_prime_mover_type[prime_mover_str]
    local bus_thermal = parse(Int, thermal_gens[i, "bus of connection"][4:6])
        local thermal = ThermalStandard(;
            name = thermal_gens[i, "Generator Name"],
            available = true,
            status = true,
            bus = buses[bus_thermal],
            active_power = 0.0,
            reactive_power = 0.0,
            rating = ratings[i],
            active_power_limits = (min = 0.0, max = 0.05),
            reactive_power_limits = (min = 0.0, max = 0.05),
            ramp_limits = (up = thermal_gens[i, "Max Ramp Up (MW/min)"], down = thermal_gens[i, "Max Ramp Down (MW/min)"]),
            operation_cost = ThermalGenerationCost(nothing),
            base_power = 0.0,
            time_limits = (up = thermal_gens[i,"Min Up Time (h)" ], down = thermal_gens[i, "Min Down Time (h)"]),
            prime_mover_type = prime_mover,
            fuel = ThermalFuels.NATURAL_GAS,
        )
    add_component!(system, thermal)
end

# Adding thermal generation cost functions
# I am assuming that the intervals are defined at the end and beginning by the end
# load points, the curve always starts at 0 and ends at the generators max
# capacity. However, there is a stable limit value that could be integrated in
# as the minimum generation level.
#Fuel Prices
ng_price = 5.4
coal_price = 1.8
oil_price = 21
bm_price = 2.4
geo_price = 0

# Mapping Fuel Prices to type of generators
# currently used a fuel price of $0 for any thermal component named "ST Other"
fuel_prices = []
for i in 1:192
    if thermal_gens[i, "PrimeMoveType"] == "OT"
        push!(fuel_prices, bm_price)
    elseif thermal_gens[i, "PrimeMoveType"] == "CC" || startswith(thermal_gens[i, "Generator Name"], "CT NG") || startswith(thermal_gens[i, "Generator Name"], "ICE NG") || startswith(thermal_gens[i, "Generator Name"], "ST NG")
        push!(fuel_prices, ng_price)
    elseif startswith(thermal_gens[i, "Generator Name"], "CT Oil")
        push!(fuel_prices, oil_price)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Coal")
        push!(fuel_prices, coal_price)
    elseif startswith(thermal_gens[i, "Generator Name"], "Geo")
        push!(fuel_prices, geo_price)
    elseif startswith(thermal_gens[i, "Generator Name"], "ST Other")
        push!(fuel_prices, 0.0)
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
    thermal_gens[:, "Load Point Band 1 (MW)"],
    thermal_gens[:, "Load Point Band 2 (MW)"],
    thermal_gens[:, "Load Point Band 3 (MW)"],
    thermal_gens[:, "Load Point Band 4 (MW)"],
    thermal_gens[:, "Load Point Band 5 (MW)"]
)
heat_rate_base = (thermal_gens[:, "Heat Rate Base (MMBTU/hr)"])/1000

# I am assuming that the intervals are defined at the end and beginning by the
# load points, the curve always starts at 0 and ends at the generators max
# capacity. However, there is a stable limit value that could be integrated in
# as the minimum generation level.

thermal_generators = collect(get_components(ThermalStandard, system))
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
            shut_down = 0.0)
    elseif !ismissing(heat_rates[i,2]) && ismissing(heat_rates[i,3])
        heat_rate = [heat_rate1[i], heat_rate2[i]]
        load_point = [load_points[i,1], load_points[i,2], max_cap]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base[i], load_point, heat_rate)
        fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
        cost = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = 0.0,
            start_up = thermal_gens[i, "Start Cost (dollar)"],
            shut_down = 0.0
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
            shut_down = 0.0
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
            shut_down = 0.0
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
            shut_down = 0.0
        )
end
    thermal_generator = thermal_generators[i]
    set_operation_cost!(thermal_generator, cost)
end
