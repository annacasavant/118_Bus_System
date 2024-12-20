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


# Reading in Time Series Data 

### Reading in Solar Time Series
```@repl system 
for i in length(solar_generator)
	solardf = CSV.read("Scripts-and-Data/TimeSeries/DA/Solar/Solar$(i)DA.csv", DataFrame) # read in data 
	norm = # Max value in time series 
	solar_array = TimeArray(timestamps, (solardf[:, 2]./norm)) # normalize data 
	solar_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = solar_array,
		   scaling_factor_multiplier = get_max_active_power, # max active power
       );
end
```

### Reading in Wind Time Series

```@repl system 
for i in length(wind_generator)
	winddf = CSV.read("Scripts-and-Data/TimeSeries/DA/Wind/Wind$(i)DA.csv", DataFrame) # read in data 
	norm = # Max value in time series
	wind_array = TimeArray(timestamps, (winddf[:, 2]./norm)) # normalize data 
	wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
		   scaling_factor_multiplier = # max active power 
       );
end
```

### Reading in Hydro Time Series 

#### With Hourly Data 

#### With Monthly Budgets 

```@repl system 
time_series_list = []
daysofmonth = [31,28,31,30,31,30,31,31,30,31,30,32]
```
```@repl system 
for i in length(hydro_with_budgets)
	time_series = []
	for row in eachrow(hydrobg[12i-11:12i, :])
		local month = # month
		for j in 1:daysofmonth[month]
			for k in 1:24
				push!(time_series, row[3]/(24*daysofmonth[month])) # create hourly data from monthly budget
			end
		end
	end
	push!(time_series_list, (time_series./maximum(time_series))) # normalize data 
end
```





