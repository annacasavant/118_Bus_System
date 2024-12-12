
## Creating the RT sys

using PowerSystems
using CSV
using DataFrames
using InfrastructureSystems
using TimeSeries
using Dates


sys_RT = System(100.0)
bus_params = CSV.read("C:/Users/acasavan/GitHub_Repos/118 Bus/bus.csv", DataFrame)
buses = []
gen_params = CSV.read("gen.csv", DataFrame)
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



## Defining Hydro Time Series ==================================================================================
resolution = Dates.Hour(1);
hydro_DA_RT_TS = []
timestamps_hyd = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);

#time series created for 16-35, 40-43
#1-15, 36-39 monthly budget modified to get hourly
#1-15 are dispatchable, rest are non-dispatchable

hydro1_15 = sort(CSV.read("HydroTimeSeries/118-hydro.csv", DataFrame), [:3])
hydro36_39 = CSV.read("HydroTimeSeries/Hydro_nondipatchable.csv", DataFrame)[21:68, 1:8]
months = []
values = []
hydro_num = []

for i in 1:length(hydro1_15[:, 1])
    if hydro1_15[i, 11] !== missing && hydro1_15[i, 4] == "Max Energy Month"
        push!(months, lpad(hydro1_15[i, 11][2:end], 2, '0'))
        push!(values, parse(Float64, hydro1_15[i, 5]))
        push!(hydro_num, hydro1_15[i, 3])
    else
        continue
    end
end

for i in 1:48
    push!(months, lpad(hydro36_39[i, 8][2:end], 2, '0'))
    push!(values, hydro36_39[i, 3])
    push!(hydro_num, hydro36_39[i, 1])
end

hydrobg = sort(DataFrame(Hydro=hydro_num, Month=months, Value=values), [:1, :2])

#constructing time series from budgets
time_series_list = []
daysofmonth = [31,28,31,30,31,30,31,31,30,31,30,32]

for i in 1:19
    time_series = []
    for row in eachrow(hydrobg[12i-11:12i, :])
        month = parse(Int, row[2])
        for j in 1:daysofmonth[month]
            for k in 1:24
                push!(time_series, row[3]/(24*daysofmonth[month]))
            end
        end
    end
    push!(time_series_list, (time_series./maximum(time_series)))
end

for i in 1:43
    if i<=15
        hydro_array = TimeArray(timestamps_hyd, time_series_list[i]/100)
        hydro_TS = SingleTimeSeries(;
           name = "max_active_power", #assumption?
           data = hydro_array,
           scaling_factor_multiplier = get_max_active_power,  #assumption?
        );
        push!(hydro_DA_RT_TS, hydro_TS);
    elseif 36<=i<=39
        hydro_array = TimeArray(timestamps_hyd, time_series_list[i-20]/100)
        hydro_TS = SingleTimeSeries(;
           name = "max_active_power", #assumption?
           data = hydro_array,
           scaling_factor_multiplier = get_max_active_power , #assumption?
        );
        push!(hydro_DA_RT_TS, hydro_TS);
    else

        hydrodf = CSV.read("HydroTimeSeries/dispatchable_cleaned/cleaned_Hydro $(i).csv", DataFrame)
        hydro_array = TimeArray(timestamps_hyd, (hydrodf[:, 2]./hydro_gens[i, "Max Capacity (MW)"])/100)
        hydro_TS = SingleTimeSeries(;
          name = "max_active_power", #assumption?
          data = hydro_array,
          scaling_factor_multiplier = get_max_active_power , #assumption?
       );
        push!(hydro_DA_RT_TS, hydro_TS);
    end
end


## Defining DA Time Series ===============================================================================================

resolution = Dates.Hour(1);
timestamps = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);
gendata = CSV.read("gen.csv", DataFrame)

## Building buses ===========================================================================================
for i in 1:118
    num = lpad(i, 3, '0')
    min_volt = bus_params[i, "Voltage-Min (pu)"]
    max_volt = bus_params[i, "Voltage-Max (pu)"]
    base_volt = bus_params[i, "Base Voltage kV"]
    bus = ACBus(;
           number = i,
           name = "bus$num",
           bustype = ACBusTypes.REF,
           angle = 0.0,
           magnitude = 1.0,
           voltage_limits = (min = min_volt, max = max_volt),
           base_voltage = base_volt,
       )
    add_component!(sys_RT, bus)
    push!(buses, bus)
end

## Building Lines ===================================================================================
# initializing an array that all
# the lines go into (i.e. to find line001, do lines18[1])
# also reading in line data to an array

line_params = CSV.read("branch.csv", DataFrame)
lines = []

# Defining all the lines and adding them to lines18

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
        add_component!(sys_RT, line)
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
        add_component!(sys_RT, tline)
        push!(lines, tline)
    end
end

# Day Ahead: =========================================================================================




## Loads RT ===============================================================================================
load_RT_TS = []

for i in 1:3
	loaddf = CSV.read("RT/Load/LoadR$(i)RT.csv", DataFrame)
	load_array = TimeArray(timestamps, (loaddf[:, 2]./maximum(loaddf[:, 2])))
	load_TS = SingleTimeSeries(;
           name = "max_active_power", #assumption?
           data = load_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(load_RT_TS, load_TS);
end

# solar: -------------------------
solar_RT_TS = []
for i in 1:75
	solardf = CSV.read("RT/Solar/Solar$(i)RT.csv", DataFrame)
	norm = solar_gens[:, "Max Capacity (MW)"]
	solar_array = TimeArray(timestamps, (solardf[:, 2]./norm[i]))
	solar_TS = SingleTimeSeries(;
           name = "max_active_power", #assumption?
           data = solar_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(solar_RT_TS, solar_TS);
end

# wind: --------------------------
wind_RT_TS = []
for i in 1:17
	winddf = CSV.read("RT/Wind/Wind$(i)RT.csv", DataFrame)
	norm = wind_gens[:, "Max Capacity (MW)"]
	wind_array = TimeArray(timestamps, (winddf[:, 2]./norm[i]))
	wind_TS = SingleTimeSeries(;
           name = "max_active_power", #assumption?
           data = wind_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(wind_RT_TS, wind_TS);
end

R1RTdf = CSV.read("RT/Load/LoadR1RT.csv", DataFrame)
R2RTdf = CSV.read("RT/Load/LoadR2RT.csv", DataFrame)
R3RTdf = CSV.read("RT/Load/LoadR3RT.csv", DataFrame)
partfact = sort!(CSV.read("ParticipationFactor.csv", DataFrame))
loads_RT_R1 = []
loads_RT_R2 = []
loads_RT_R3 = []

R1_buses = []
R2_buses = []
R3_buses = []


for i in 1:118
    if bus_params[i, "Area"] == "R1"
        push!(R1_buses, bus_params[i, "Number"])
    elseif bus_params[i, "Area"] == "R2"
        push!(R2_buses, bus_params[i, "Number"])
    elseif bus_params[i, "Area"] == "R3"
        push!(R3_buses, bus_params[i, "Number"])
    end
end


# Defining all the loads and adding them to lists =============================================================================
# adding loads and time series into toy_system_2

for i in 1:118
	num = lpad(i, 3, '0')
	if parse(Int, partfact[i, 2][2]) == 1
		max1 = maximum(R1RTdf[:, 2])
		load = PowerLoad(;
    		name = "load$num",
    		available = true,
    		bus = buses[i],
    		active_power = 0.0, #per-unitized by device base_power
    		reactive_power = 0.0, #per-unitized by device base_power
    		base_power = 100.0, # MVA, for loads match system
    		max_active_power = (max1)*(partfact[i, 3]), #per-unitized by device base_power?
    		max_reactive_power = 0.0,
    	);
		add_component!(sys_RT, load)
		push!(loads_RT_R1, load)
	elseif parse(Int, partfact[i, 2][2]) == 2
		max2 = maximum(R2RTdf[:, 2])
		load = PowerLoad(;
    		name = "load$num",
    		available = true,
    		bus = buses[i],
    		active_power = 0.0, #per-unitized by device base_power
    		reactive_power = 0.0, #per-unitized by device base_power
    		base_power = 100.0, # MVA, for loads match system
    		max_active_power = (max2)*(partfact[i, 3]), #per-unitized by device base_power?
    		max_reactive_power = 0.0,
    	);
		add_component!(sys_RT, load)
		push!(loads_RT_R2, load)
	else parse(Int, partfact[i, 2][2]) == 3
		max3 = maximum(R3RTdf[:, 2])
		load = PowerLoad(;
    		name = "load$num",
    		available = true,
    		bus = buses[i],
    		active_power = 0.0, #per-unitized by device base_power
    		reactive_power = 0.0, #per-unitized by device base_power
    		base_power = 100.0, # MVA, for loads match system
    		max_active_power = (max3)*(partfact[i, 3]), #per-unitized by device base_power?
    		max_reactive_power = 0.0,
    	);
		add_component!(sys_RT, load)
		push!(loads_RT_R3, load)
	end
end


associations1 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[1],)
    for load in loads_RT_R1
)
bulk_add_time_series!(sys_RT, associations1)

associations2 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[2],)
    for load in loads_RT_R2
)
bulk_add_time_series!(sys_RT, associations2)

associations3 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[3],)
    for load in loads_RT_R3
)
bulk_add_time_series!(sys_RT, associations3)


## Building Generators and attaching DA time series =========================================================================================================

#building the solar gens
bus_solar = []
solar_RT_gens = []
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
        base_power = 0.00
        )
    add_component!(sys_RT, solar)
	add_time_series!(sys_RT, solar, solar_RT_TS[i])
	push!(solar_RT_gens, solar)
end

#building the wind gens
bus_wind = []
wind_RT_gens = []
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
        base_power = 0.00
        )
    add_component!(sys_RT, wind)
	add_time_series!(sys_RT, wind, wind_RT_TS[i])
	push!(wind_RT_gens, wind)
end


# Building Hydro Generators and Attaching Time Series  ===============================================================================
    # Parsing ramp up and down values -------------
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
    hydro_TS = get_data(hydro_DA_RT_TS[i])
    initial_active_power = hydro_TS[1]
    num = lpad(i, 3, '0')
    bus_hydro = parse(Int, hydro_gens[i, "bus of connection"][4:6])
    hydro = HydroDispatch(;
        name = "hydro$num",
        available = true,
        bus = buses[bus_hydro],
        active_power = initial_active_power[i],
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
    add_component!(sys_RT, hydro)
    push!(hydro_DA_RT_gens, hydro)
    add_time_series!(sys_RT, hydro, hydro_DA_RT_TS[i])
end

# building thermal gens
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
    # FUel Prices
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
#What are the reactive power ramp_limits
#Assuming the active power limits are [0 -> Max Capacity (MW)]
#Assuming device base is the same as system base 100 MW
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
            rating = ratings[i],
            active_power_limits = (min = min_active_power, max = max_active_power),
            reactive_power_limits = (min = 0.0, max = 0.0),
            ramp_limits = (up = thermal_gens[i, "Max Ramp Up (MW/min)"], down = thermal_gens[i, "Max Ramp Down (MW/min)"]),
            operation_cost = ThermalGenerationCost(nothing),
            base_power = 100,
            time_limits = (up = thermal_gens[i,"Min Up Time (h)" ], down = thermal_gens[i, "Min Down Time (h)"]),
            prime_mover_type = prime_mover,
            fuel = fuel[i],
        )
    add_component!(sys_RT, thermal)
end

# Adding thermal generation cost functions
# I am assuming that the intervals are defined at the end and beginning by the end
# load points, the curve always starts at 0 and ends at the generators max
# capacity. However, there is a stable limit value that could be integrated in
# as the minimum generation level.


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

thermal_generators = collect(get_components(ThermalStandard, sys_RT))
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










