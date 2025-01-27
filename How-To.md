# Building a System from CSV Files

### Dependencies
```@hide
using PowerSystems 
using CSV
using DataFrames
```
### Build the base of the system with appropriate base power. 
Begin by building the base system using the base power. 

```@repl system 
sys = System(100)
```
### Read in all component data 
Read in the CSV files that contain the data for building the system. In this example, the line, bus and generator data are found in the following CSV files. 
```@repl system 
line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)
gen_params = CSV.read("Scripts-and-Data/gen.csv", DataFrame) 
```

### Build the buses - parsing data from `bus_params`
The first building block are the buses in the system. We can define variables describing the buses using columns found in the `bus_params.csv` file. In this example we are defining the minimum voltage, maximum voltage and base voltage. 
```@repl system 
min_voltage_col_name = "Voltage-Min (pu)"
max_voltage_col_name = "Voltage-Max (pu)"
base_voltage_col_name = "Base Voltage"
```
```@repl system
buses = []
for row in eachrow(bus_params)
    #num =  lpad(string(row, 3, '0'))
    min_volt = row[:min_voltage_col_name]     
    max_volt = row[:max_voltage_col_name]
    base_volt = row[:base_voltage_col_name]
    bus = ACBus(;
           number = row[:number],
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
The next step is to build the lines and transformers in the system which are stored in the same CSV. A component is a line if the buses being connected have the same base voltage, and a transformer if they have different base voltages. 

Begin by defining variables describing the lines/transformers using the columns found in the `line_params` dataframe. 
```@repl system 
bus_from = "Bus from"
bus_to = "Bus to" 
reactance = "Reactance (p.u.)"
resistance = "Resistance (p.u.)"
max_flow = "Max Flow (MW)"
min_flow = "Min Flow (MW)"
```

```@repl system 
for row in eachrow(line_params) 
    num = lpad(rownumber(row), 3, '0')
    bus_from = parse(Int, row[bus_from][4:6])
    bus_to = parse(Int, row[bus_to][4:6])
    if bus_params[bus_to, base_voltage_col_name] == bus_params[bus_from, base_voltage_col_name] #if the base voltage of buses being connected are the same, build a line
        local line = Line(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row[resistance],
            x = row[reactance],
            b = (from = 0.0, to = 0.0),
            rating = row[max_flow]/100,
            angle_limits = (min = 0.0, max = 0.0),
        );
        add_component!(sys_DA, line)
		add_component!(sys_RT, line)
    else # if the base voltages of the connecting buses do not match build a transformer
        local tline = Transformer2W(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row[resistance],
            x = row[reactance],
            primary_shunt = 0.0,
            rating = row[max_flow]/100,
        );
        add_component!(sys_DA, tline)
		add_component!(sys_RT, tline)
    end
end
```

# Building Generator Components


In this step we are creating dataframes characterized by the generator type because thermal generators, hydro generators and renewable generators are different types of components.   

```@repl system 
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
```

The next step is to build the generators by parsing data from `gen_params`. We can define variables describing the generators using columns found in the `gen_params`. 
```@repl system 
name = "Generator Name"
bus_connection = "bus of connection"
rate = "Rating"
min_active_power = "Min Stable Level (MW)"
max_active_power = "Max Capacity (MW)"
ramp_up = "Max Ramp Up (MW/min)"
ramp_down = "Max Ramp Down (MW/min)"
min_down = "Min Down Time (h)"
min_up = "Min Up Time (h)"
prime_move = "PrimeMoveType"
```


## Building Thermal Generators
Build the thermal generators using the `thermal_gens` dataframe. 
```@repl system 
for row in eachrow(thermal_gens)
        bus = row[bus_connection]
        local thermal = ThermalStandard(;
            name = row[name], 
            available = true,
            status = true,
            bus = get_bus(sys_DA, bus),
            active_power = 0,
            reactive_power = 0,
            rating = row[rate],
            active_power_limits = (min = row[min_active_power], row[max = max_active_power])
            reactive_power_limits = (min = 0.0, max = 0.0)
            ramp_limits = (up = row[ramp_up], down = row[ramp_down]),
            operation_cost = ThermalGenerationCost(nothing), 
            base_power = 100,
            time_limits = ( up = row[min_up], down = row[min_down]),
            prime_mover_type = row[prime_move],
            fuel = row[fuel],
        )
    add_component!(sys, thermal) 
end
``` 

# Build solar generators - parsing data from the `solar_gens` data frame
Using similar logic as the previous section, let's build the solar generators. 

```@repl system
for row in eachrow(solar_gens)
bus = row[bus_connection]
    local solar = RenewableDispatch(;
        name = row[name],
        available = true,
        bus = get_bus(sys_DA, bus)
        active_power = 0,
        reactive_power = 0,
        rating = row[rate], 
        prime_mover_type = PrimeMovers.PVe,
        reactive_power_limits = (min = 0.0, max = 0.0),
        power_factor = 1.0
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100
        )
    add_component!(sys, solar)
```

### Build wind generators - parsing data from the `wind_gens` data frame

```@repl system

for row in eachrow(wind_gens)
    bus = row[bus_connection]
    local wind = RenewableDispatch(;
        name = row[name],
        available = true,
        bus = get_bus(sys_DA, bus),
        active_power = 0,
        reactive_power = 0, 
        rating = row[rate],
        prime_mover_type = PrimeMovers.WT,
        reactive_power_limits = (min = 0.0, max = 0.0),
        power_factor = 1.0
        operation_cost = RenewableGenerationCost(nothing),
        base_power = 100
        )
    add_component!(sys, wind)
end
```
### Build hydro generators - parsing data from the `hydro_gens` data frame 
```@repl system 
for row in eachrow(hydro_gens)
    bus = row[bus_connection]
    local hydro = HydroDispatch(;
        name = row[name]
        available = true,
        bus = get_bus(sys_DA, bus),
        active_power = 0.0,
        reactive_power = 0.0,
        rating = row[rate],
        prime_mover_type = PrimeMovers.HA,
        active_power_limits = (min = row[min_active_power]/100, max = row[min_active_power]/100),
        reactive_power_limits = (min = 0.0, max = 0.0),
        ramp_limits = (up = row[ramp_up], down = row[ramp_down]),
        time_limits = (up = row[min_up], down = row[min_down]),
        base_power = 100,
        operation_cost = HydroGenerationCost(nothing)
        )
    add_component!(sys_DA, hydro)
end
```

# Building `RenewableGenerationCost`, `HydroGenerationCost` and `ThermalGenerationCost` functions
The next step is to build attach the respective cost function to the generators. The cost function data is found in the `gen_params` data frame.  

### `RenewableGenerationCost`
For the renewable generators assume zero marginal cost. Therefore there is a `zero(CostCurve)`. Use the `set_operation_cost!` function to attach the cost function to the respective generators. 
```@repl system 
ren_gens = collect(get_components(RenewableDispatch, sys)) #collect the renewable generators in a vector
for i in length(renewable_generation)
    cost_curve = zero(CostCurve) 
    cost_ren = RenewableGenerationCost(cost_curve)
    ren_gen = ren_gens[i] 
    set_operation_cost!(ren_gen, cost_ren)
end
``` 
For more information regarding renewable cost function please visit [RenewableGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/renewable_generation_cost/#RenewableGenerationCost).

### `HydroGenerationCost`
Hydro generation costs are defined by a fixed and variable cost. In this example assume both are zero. 
```@repl system 
hydrogens = collect(get_components(HydroDispatch, sys)) #collect hydro generators
for i in length(hydro_generators)
    curve = LinearCurve(0.0)
    value_curve = CostCurve(curve) # This can either be a CostCurve() or FuelCurve()
    fixed = 0.0 
    cost_hydro = HydroGenerationCost(;variable = value_curve, fixed)
    hydrogen = hydrogens[i]
    set_operation_cost!(hydrogens[i], cost_hydro)
end
```
For more information regarding hydro cost functions please visit [HydroGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/hydro_generation_cost/). 

### `ThermalGenerationCost`
In this case the thermal generator cost is defined by fuel curves not cost curves. Begin by importaing and parsing the CSV that describes fuel costs. 
```@repl system 
fuel_params = CSV.read("Scripts-and-Data\\Fuels and emission rates.csv", DataFrame)
fuel_cost = Dict(
    "coal" => fuel_params[1, 2],
    "ng" => fuel_params[2, 2],
    "oil" => fuel_params[3, 2],
    "bio" => fuel_params[4, 2],
    "geo" => fuel_params[5, 2],
)
```
Assign a fuel type and price to the generators based on their name.  
```@repl system 
fuel_prices = []
fuel = []
for row in eachrow(thermal_gens)
    if row[prime_move] == "OT"
        push!(fuel_prices, bm_price)
        push!(fuel, ThermalFuels.AG_BIPRODUCT)
    elseif row[name] == "CC" || startswith(row[name], "CT NG") || startswith(row[name], "ICE NG") || startswith(row[name], "ST NG")
        push!(fuel_prices, ng_price)
        push!(fuel, ThermalFuels.NATURAL_GAS)
    elseif startswith(row[name], "CT Oil")
        push!(fuel_prices, oil_price)
        push!(fuel, ThermalFuels.DISTILLATE_FUEL_OIL)
    elseif startswith(row[name], "ST Coal")
        push!(fuel_prices, coal_price)
        push!(fuel, ThermalFuels.COAL)
    elseif startswith(row[name], "Geo")
        push!(fuel_prices, geo_price)
        push!(fuel, ThermalFuels.GEOTHERMAL)
    elseif startswith(row[name], "ST Other 01")
        push!(fuel_prices, oil_price)
        push!(fuel, ThermalFuels.DISTILLATE_FUEL_OIL)
    elseif startswith(row[name], "ST Other 02")
        push!(fuel_prices, ng_price)
        push!(fuel, ThermalFuels.NATURAL_GAS)
    end
end
```
### Parse heat rates, load points and heat rate bases. 
Heat rates, load points, and heat rate bases are used to construct linear and piecewise fuel curves that describe the operational cost of the thermal units. 
```@repl system 
heat_rate_base = thermal_gens[:, "Heat Rate Base (MMBTU/hr)"]
heat_rate = thermal_gens[:, "Heat Rate (MMBTU/hr)"]
load_point = thermal_gen[:, "Load Point Band (MW)"]
fixed_cost = thermal_gen[: "Fixed Cost"]
start_up_cost = thermal_gen[:, "Start Up Cost"]
shut_down_cost = thermal_gen[:. "Shut Down Cost"]
```
Using the heat rate bases, heat rates, load points and fuel costs, we can construct the thermal generation cost functions. 
```@repl system 
thermals = collect(get_components(ThermalStandard, sys)) # collect thermal generators 
for row in eachrow(thermal_gens) 
   fuel_cost = row[fuel_prices]
   heat_rate_base = row[heat_rate_base]
   heat_rate = row[heat_rate]
   load_point = row[load_point]
   heat_rate_curve = PieceWiseIncrementalCurve(heat_rate_base[i], load_point[i], heat_rate[i])
   fuel_curve FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_prices[i])
   cost_thermal = ThermalGenerationCost(;
            variable = fuel_curve,
            fixed = row[fixed_cost]
            start_up = row[start_up_cost]
            shut_down = row[shut_down_cost]
        )
        set_operation_cost!(thermals[i], cost_thermal)
end
```
For more information regarding thermal cost functions please visit [ThermalGenerationCost](https://nrel-sienna.github.io/PowerSystems.jl/stable/model_library/thermal_generation_cost/). 


