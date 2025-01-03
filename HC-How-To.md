# Building a System with Real Time and Forecast

### Dependencies
```@repl system 
using PowerSystems 
using CSV
using DataFrames
```
### Build the base of the system with appropriate base power. 

```@repl system 
sys = System(100)
```
### Read in all component data 
```@repl system 
line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)
gen_params = CSV.read("Scripts-and-Data/gen.csv", DataFrame) 
```

### Build the buses - parsing data from `bus_params`

```@repl system 
buses = []
for i in 1:118
    num = lpad(i, 3, '0') 
    min_volt = bus_params[i, "Voltage-Min (pu)"] 
    max_volt = bus_params[i, "Voltage-Max (pu)"]
    base_volt = bus_params[i, "Base Voltage kV"]
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
end
```

### Build the lines and transformers - parsing data from `line_params`

```@repl system 
for i in length(lines)
    if # voltage at connecting ends is the same - build a line
        local line = Line(;
            name = # name
            available = true,
            active_power_flow = # parsed data,
            reactive_power_flow = # parsed data,
            arc = # parsed data,
            r = # parsed data,
            x = # parsed data,
            b = # parsed data,
            rating = # parsed data,,
            angle_limits = # parsed data,
        );
        add_component!(sys, line)
    else # voltage at connecting ends is different - build a transformer
        local tline = Transformer2W(;
            name = # name 
            available = true,
            active_power_flow = # parsed data,
            reactive_power_flow = # parsed data,
            arc = # parsed data,
            r = # parsed data,
            x = # parsed data,
            primary_shunt = # parsed data,
            rating = # parsed data,
        );
        add_component!(sys, tline)
    end
end
```

# Reading in Time Series Data 
```julia
resolution = Dates.Hour(1);
timestamps = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);
```

### Reading in Load Time Series
```julia
load_DA_TS = []

for i in 1:3
    local loaddf = CSV.read("Scripts-and-Data/TimeSeries/DA/Load/LoadR$(i)DA.csv", DataFrame)
    local load_array = TimeArray(timestamps, (loaddf[:, 2]./maximum(loaddf[:, 2])))
    local load_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = load_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
       );
    push!(load_DA_TS, load_TS);
end
```

### Reading in Solar Time Series
```@repl system 
solar_RT_TS = []

for i in 1:75
    local solardf = CSV.read("Scripts-and-Data/TimeSeries/RT/Solar/Solar$(i)RT.csv", DataFrame)
    local norm = parse(Float64, replace(gendata[i+223,5], ',' => '.'))
    local solar_array = TimeArray(timestamps, (solardf[:, 2]./norm))
    local solar_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = solar_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
       );
    push!(solar_RT_TS, solar_TS);
end
```

### Reading in Wind Time Series
```@repl system 
wind_RT_TS = []

for i in 1:17
    local winddf = CSV.read("Scripts-and-Data/TimeSeries/RT/Wind/Wind$(i)RT.csv", DataFrame)
    local norm = parse(Float64, replace(gendata[i+311,5], ',' => '.'))
    local wind_array = TimeArray(timestamps, (winddf[:, 2]./norm))
    local wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
       );
    push!(wind_RT_TS, wind_TS);
end
```

### Reading in Hydro Time Series 

#### Correcting Data to be Hourly 

```julia
hydro_DA_RT_TS = []

#time series created for 16-35, 40-43
#1-15, 36-39 monthly budget modified to get hourly
#1-15 are dispatchable, rest are non-dispatchable

hydro1_15 = sort(CSV.read("Scripts-and-Data/TimeSeries/Hydro/118-hydro.csv", DataFrame), [:3])
hydro36_39 = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro_nondispatchable.csv", DataFrame)[21:68, 1:8]
months = []
values = []
hydro_num = []

for i in 1:length(hydro1_15[:, 1])
    if hydro1_15[i, 11] !== missing && hydro1_15[i, 4] == "Max Energy Month"
        push!(months, lpad(hydro1_15[i, 11][2:end], 2, '0'))
        push!(values, parse(Float64, hydro1_15[i, 5]))
        push!(hydro_num, hydro1_15[i, 3])
    end
end

for i in 1:48
    push!(months, lpad(hydro36_39[i, 8][2:end], 2, '0'))
    push!(values, hydro36_39[i, 3])
    push!(hydro_num, hydro36_39[i, 1])
end

hydrobg = sort(DataFrame(Hydro=hydro_num, Month=months, Value=values), [:1, :2])
```

#### Creating Hydro Time Series Array

```julia 
time_series_list = []
daysofmonth = [31,28,31,30,31,30,31,31,30,31,30,32]

for i in 1:19
    local time_series = []
    for row in eachrow(hydrobg[12i-11:12i, :])
        local month = parse(Int, row[2])
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
        local hydro_array = TimeArray(timestamps, time_series_list[i])
        local hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
        );
        push!(hydro_DA_RT_TS, hydro_TS);
    elseif 36<=i<=39
        local hydro_array = TimeArray(timestamps, time_series_list[i-20])
        local hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
        );
        push!(hydro_DA_RT_TS, hydro_TS);
    else
        local hydrodf = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro$(i).csv", DataFrame)
        deleteat!(hydrodf, 1417:1440)
        local hydro_array = TimeArray(timestamps, (hydrodf[:, 2]./maximum(hydrodf[:, 2])))
        local hydro_TS = SingleTimeSeries(;
          name = "max_active_power",
          data = hydro_array,
          scaling_factor_multiplier = get_max_active_power, #assumption?
       );
        push!(hydro_DA_RT_TS, hydro_TS);
    end
end
```

# Building Generator Components
### Build thermal generators - parsing data from `gen_params`

```@repl system 
for i in length(thermal_generators)
        thermal = ThermalStandard(;
            name = # name,  
            available = true,
            status = true,
            bus = # parsed data,
            active_power = # parsed data,
            reactive_power = # parsed data,
            rating = # parsed data,
            active_power_limits = # parsed data,
            reactive_power_limits = # parsed data,
            ramp_limits = # parsed data,
            operation_cost = ThermalGenerationCost(nothing), 
            base_power = 100,
            time_limits = # parsed data,
            prime_mover_type = # parsed data,
            fuel = # parsed data,
        )
    add_component!(sys, thermal)
end
``` 

### Build solar generators - parsing data from `gen_params`
```@repl system
for i in length(solar_generators)
    local solar = RenewableDispatch(;
        name = # name
        available = true,
        bus = # bus of connection
        active_power = # active power
        reactive_power = # reactive power
        rating = # generator rating 
        prime_mover_type = PrimeMovers.PVe,
        reactive_power_limits = # reactive power limits
        power_factor = # power factor
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100
        )
    add_component!(sys, solar)
```

### Build wind generators - parsing data from `gen_params`

```@repl system

for i in length(wind_generators)
    wind = RenewableDispatch(;
        name = # name
        available = true,
        bus = # bus of connection
        active_power = # initial active power
        reactive_power = # initial reactive power
        rating = # generator rating 
        prime_mover_type = PrimeMovers.WT,
        reactive_power_limits = # reactive power limits
        power_factor = # power factor
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100
        )
    add_component!(sys, wind)
end
```
### Build hydro generators - parsing data from `gen_params` 
```@repl system 

for i in length(hydro_generation)
    local hydro = HydroDispatch(;
        name = "hydro$num",
        available = true,
        bus = buses[bus_hydro],
        active_power = 0.0,
        reactive_power = 0,
        rating = 0.0,
        prime_mover_type = PrimeMovers.HA,
        active_power_limits = (min = hydro_gens[i, "Min Stable Level (MW)"]/100, max = hydro_gens[i, "Max Capacity (MW)"]/100),
        reactive_power_limits = (min = 0.0, max = 0.0),
        ramp_limits = (up = hydro_gens[i, "Max Ramp Up (MW/min)"], down = hydro_gens[i, "Max Ramp Down (MW/min)"]),
        time_limits = (up = hydro_gens[i,"Min Up Time (h)" ], down = hydro_gens[i, "Min Down Time (h)"]),
        base_power = 100,
        operation_cost = HydroGenerationCost(nothing)
        )
    add_component!(sys_DA, hydro)
	push!(hydro_DA_RT_gens, hydro)
	add_time_series!(sys_DA, hydro, hydro_DA_RT_TS[i])
end
```

# Building `RenewableGenerationCost`, `HydroGenerationCost` and `ThermalGenerationCost` functions

### `RenewableGenerationCost`
```@repl system 
ren_gens = collect(get_components(RenewableDispatch, sys)) #collect the renewable generators
for i in length(renewable_generation)
    cost_curve = zero(CostCurve) 
    cost_ren = RenewableGenerationCost(cost_curve)
    ren_gen = ren_gens[i] 
    set_operation_cost!(ren_gen, cost_ren)
end
``` 
For more information regarding renewable cost function please visit [RenewableGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/renewable_generation_cost/#RenewableGenerationCost).
### `HydroGenerationCost`
```@repl system 
hydrogens = collect(get_components(HydroDispatch, sys)) #collect hydro generators
for i in length(hydro_generators)
    curve = LinearCurve(0.0)
    value_curve = # FuelCurve(curve) or CostCurve(curve)
    fixed = # fixed cost 
    cost_hydro = HydroGenerationCost(;variable = value_curve, fixed)
    hydrogen = hydrogens[i]
    set_operation_cost!(hydrogens[i], cost_hydro)
end
```
For more information regarding hydro cost functions please visit [HydroGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/hydro_generation_cost/). 
### `ThermalGenerationCost`
```@repl system 
thermals = collect(get_components(ThermalStandard, sys)) # collect thermal generators 
for i in length(thermals)
   fuel_cost = # fuel prices
   heat_rate_base = # heat rate base
   heat_rate = # heat rates
   load_point = # load points 
   heat_rate_curve = PieceWiseIncrementalCurve(heat_rate_base[i], load_point[i], heat_rate[i])
   fuel_curve FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
   cost_thermal = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = # fixed cost 
            start_up = # start up cost
            shut_down = # shut down cost
        )
        set_operation_cost!(thermals[i], cost_thermal)
end
```
For more information regarding thermal cost functions please visit [ThermalGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/thermal_generation_cost/). 


