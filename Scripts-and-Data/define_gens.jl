#=
In this script, we're building all the renewable and thermal generators. The
first for loop and conditional is building RenewableDispatch and HydroDispatch
by isolating the rows of gen_params that describe those generator types.
I would've used IS.deserialize for the renewable gens, but in gen.csv, the
solar prime mover type is "Pve" instead of "PVe".
Then after that, their cost functions are attached. After that is when we
build the ThermalStandards and their cost functions.

How to deal with base_power:
If we have rating but not base power, do:
    base_power = row[RATE]; rating = 1.0
If we don't have rating or base power, do:
    base_power = row[MAX_CAP]; rating = 1.0; 
    active_power_limits = (min = 0.0, max = 1.0) 

Heat rates and load points dictionaries: 
Previously vectors were created manually in a conditional statement that sorted
the creation of cost functions by how many heat rate bands there were, (band 1;
bands 1 and 2; up to bands 1 through 5). Edit was made in order to make these
vectors before the cost function step, and they are attached to a dictionary
key of the generator's name. The heat rate vectors go by bands [1, 2, 3, 4, 5] 
and if any of the bands are missing, they are filtered out of the vector. 
Similarly, load point vectors go [MIN_STABLE, 1, 2, 3, 4, MAX_CAP] and filtered 
by the not missing values. Load point band 5 is omitted since the data is either 
missing, or equal to MAX_CAP.  With this change, all the 
PiecewiseIncrementalCurves can be added at once, since the vectors are already 
formatted properly. When creating thermal_gens dataframe, I convert unnecessary 
load points to missing. For instance, if the heat rate vector is only HR1 and 
HR2, the rest of the band values are missing, the only load point band needed is
LP1, but sometimes the dataframe includes higher band values anyways, which 
PiecewiseIncrementalCurve doesn't like, if you just give it all the load point 
bands for each generator.
=#

# creating dataframe for gens paramaters, and variables for column names 

gen_params = CSV.read("Scripts-and-Data/gen.csv", DataFrame)

TYPE = "type"
PRIME = "PrimeMoveType"
NAME = "Generator Name"
BUS = "bus of connection"
RATE = "Rating"
MAX_CAP = "Max Capacity (MW)"
MIN_STABLE = "Min Stable Level (MW)"
RAMP_UP = "Max Ramp Up (MW/min)"
RAMP_DOWN = "Max Ramp Down (MW/min)"
UP_TIME = "Min Up Time (h)"
DOWN_TIME = "Min Down Time (h)"
START_COST = "Start Cost (dollar)"

# building Hydro and Renewable Generators ========================================================

for row in eachrow(gen_params)
    if row[TYPE] == "Solar" || row[TYPE] == "Wind"
        if row[TYPE] == "Solar"
            prime = PrimeMovers.PVe
        elseif row[TYPE] == "Wind"
            prime = PrimeMovers.WT
        end
        local bus_renew = get_bus(sys_DA, row[BUS])
        local renew = RenewableDispatch(;
            name = row[NAME],
            available = true,
            bus = bus_renew,
            active_power = 0.0,
            reactive_power = 0.0,
            rating = 1.0,
            prime_mover_type = prime,
            reactive_power_limits = (min = 0.0, max = 0.0),
            power_factor = 1.0,
            operation_cost = RenewableGenerationCost(nothing),
            base_power = row[MAX_CAP],
        )
        add_component!(sys_DA, renew)
    elseif row[TYPE] == "Hydro"
        local bus_hydro = get_bus(sys_DA, row[BUS])
        base = row[MAX_CAP]
        local hydro = HydroDispatch(;
            name = row[NAME],
            available = true,
            bus = bus_hydro,
            active_power = 0.0,
            reactive_power = 0.0,
            rating = 1.0,
            prime_mover_type = PrimeMovers.HA,
            active_power_limits = (min = 0.0, max = 1.0),
            reactive_power_limits = (min = 0.0, max = 0.0),
            ramp_limits = (up = row[RAMP_UP]/base, down = row[RAMP_DOWN]/base),
            time_limits = (up = row[UP_TIME], down = row[DOWN_TIME]),
            base_power = base,
            operation_cost = HydroGenerationCost(nothing),
        )
        add_component!(sys_DA, hydro)
    end
end

# Making RenewableGenerationCost functions assume no VOM cost and no curtailment cost

for renew in collect(get_components(RenewableDispatch, sys_DA))
    cost_curve = zero(CostCurve)
    ren_cost = RenewableGenerationCost(cost_curve)
    set_operation_cost!(renew, ren_cost)
end

# Making HydroGenerationCost 

for hydros in collect(get_components(HydroDispatch, sys_DA))
    cost_curve = LinearCurve(0.0)
    value_curve = CostCurve(cost_curve)
    fixed = 0.0
    hydro_cost = HydroGenerationCost(;variable = value_curve, fixed)
    set_operation_cost!(hydros, hydro_cost)
end

# building thermal gens ==========================================================================

# more column name variables

HRB = "Heat Rate Base (MMBTU/hr)"
HR1 = "Heat Rate Inc Band 1 (BTU/kWh)"
HR2 = "Heat Rate Inc Band 2 (BTU/kWh)"
HR3 = "Heat Rate Inc Band 3 (BTU/kWh)"
HR4 = "Heat Rate Inc Band 4 (BTU/kWh)"
HR5 = "Heat Rate Inc Band 5 (BTU/kWh)"
LP1 = "Load Point Band 1 (MW)"
LP2 = "Load Point Band 2 (MW)"
LP3 = "Load Point Band 3 (MW)"
LP4 = "Load Point Band 4 (MW)"

# create thermal_gens dataframe from gen_params dataframe

thermal_gens = DataFrame()

for row in eachrow(gen_params)
    if row[TYPE] == "Thermal "
        for i in 3:5
            if ismissing(row["Heat Rate Inc Band $i (BTU/kWh)"])
                row["Load Point Band $(i-1) (MW)"] = missing
            end
        end
        push!(thermal_gens, row, promote=true)
    end
end

# Fuel Prices

ng_price = 5.4
coal_price = 1.8
oil_price = 21
bm_price = 2.4
geo_price = 0

# Mapping Fuel Prices and type to type of generators, creating heat rate and load point dictionaries

fuel_cost_dict = Dict()
fuel_type_dict = Dict()
heat_rates = Dict()
load_points = Dict()

for row in eachrow(thermal_gens)
    if row[PRIME] == "OT"
        fuel_cost_dict[row[PRIME]] = bm_price
        fuel_type_dict[row[PRIME]] = ThermalFuels.AG_BYPRODUCT
    elseif row[PRIME] == "CC" || startswith(row[NAME], "CT NG") || startswith(row[NAME], "ICE NG") || startswith(row[NAME], "ST NG") || startswith(row[NAME], "ST Other 02")
        fuel_cost_dict[row[PRIME]] = ng_price
        fuel_type_dict[row[PRIME]] = ThermalFuels.NATURAL_GAS
    elseif startswith(row[NAME], "CT Oil") || startswith(row[NAME], "ST Other 01")
        fuel_cost_dict[row[PRIME]] = oil_price
        fuel_type_dict[row[PRIME]] = ThermalFuels.DISTILLATE_FUEL_OIL
    elseif startswith(row[NAME], "ST Coal")
        fuel_cost_dict[row[PRIME]] = coal_price
        fuel_type_dict[row[PRIME]] = ThermalFuels.COAL
    elseif startswith(row[NAME], "Geo")
        fuel_cost_dict[row[PRIME]] = geo_price
        fuel_type_dict[row[PRIME]] = ThermalFuels.GEOTHERMAL
    end
    heat_rates[row[NAME]] = filter!(x->!ismissing(x), [row[HR1], row[HR2], row[HR3], row[HR4], row[HR5]]./1000)
    load_points[row[NAME]] = filter!(x->!ismissing(x), [row[MIN_STABLE], row[LP1], row[LP2], row[LP3], row[LP4], row[MAX_CAP]])
end

# I am assuming that the intervals are defined at the end and beginning by the
# load points, the curve always starts at the minimum stable level and ends at the generators max
# capacity.  

thermal_cost_function = Dict()

# After manipulating the heat_rates data, 101 gens should have LinearCurves, which matches number from old method

for row in eachrow(thermal_gens)
    heat_rate_base = row[HRB]/1000
    if length(heat_rates[row[NAME]]) == 1
        heat_rate_curve = LinearCurve(row[HR1]/1000, heat_rate_base)
    else
        heat_rate = heat_rates[row[NAME]]
        load_point = load_points[row[NAME]]
        heat_rate_curve = PiecewiseIncrementalCurve(heat_rate_base, load_point, heat_rate)
    end
    fuel_curve = FuelCurve(; value_curve = heat_rate_curve, fuel_cost = fuel_cost_dict[row[PRIME]])
    cost = ThermalGenerationCost(;
        variable = fuel_curve,
        fixed = 0.0,
        start_up = row[START_COST],
        shut_down = 0.0
    )
    thermal_cost_function[row[NAME]] = cost
end

for row in eachrow(thermal_gens)
    bus_thermal = get_bus(sys_DA, row[BUS])
    prime = IS.deserialize(PrimeMovers, convert(String, row[PRIME]))
    if ismissing(row[RATE]) || row[RATE] == ""
        base = row[MAX_CAP]
        max_active = 1.0
        min_active = 0.0
    else
        base = parse(Float64, row[RATE])
        max_active = row[MAX_CAP]/base
        min_active = row[MIN_STABLE]/base
    end
    thermal = ThermalStandard(;
        name = row[NAME],
        available = true,
        status = true,
        bus = bus_thermal,
        active_power = 0.0,
        reactive_power = 0.0,
        rating = 1.0,
        active_power_limits = (min = min_active, max = max_active),
        reactive_power_limits = nothing,
        ramp_limits = (up = row[RAMP_UP]/base, down = row[RAMP_DOWN]/base),
        operation_cost = ThermalGenerationCost(nothing),
        base_power = base,
        time_limits = (up = row[UP_TIME], down = row[DOWN_TIME]),
        prime_mover_type = prime,
        fuel = fuel_type_dict[row[PRIME]],
    )
    add_component!(sys_DA, thermal)
    set_operation_cost!(thermal, thermal_cost_function[row[NAME]])
end
