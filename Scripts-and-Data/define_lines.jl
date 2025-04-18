#=
This script builds the branches of the system. We build either a line, if the
connecting buses have the same base voltage, or a transformer2w if they have 
different base voltages. Lines.csv contains Min Flow data that we aren't using 
as the Line or Transformer2W constructors don't require them. "Bus from" and 
"Bus to" columns formatted as "bus001", to match naming convention of buses 
used in previous script. Other hard coded variables are because our data didn't 
specify them.

Because raw data does not have rating, rating is the max flow, per-unitized
by the system base power. And since branches don't have (device) base power
variable, assume it would be the system base power.
=#

# reading in line data to a dataframe and defining column names as variables

line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)

NAME = "Line Name"
BUS_FROM = "Bus from "
BUS_TO = "Bus to"
REACT = "Reactance (p.u.)"
RESIST = "Resistance (p.u.)"
MAX_FLOW = "Max Flow (MW)"

# defining all the branches

for row in eachrow(line_params) 
    bus_from = get_bus(sys_DA, row[BUS_FROM])
    bus_to = get_bus(sys_DA, row[BUS_TO])
    if get_base_voltage(bus_to) == get_base_voltage(bus_from)
        local line = Line(;
            name = row[NAME],
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = bus_from, to = bus_to),
            r = row[RESIST],
            x = row[REACT],
            b = (from = 0.0, to = 0.0),
            rating = row[MAX_FLOW]/system_base_power,
            angle_limits = (min = 0.0, max = 0.0),
        );
        add_component!(sys_DA, line)
    else
        local tline = Transformer2W(;
            name = row[NAME],
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = bus_from, to = bus_to),
            r = row[RESIST],
            x = row[REACT],
            primary_shunt = 0.0,
            rating = row[MAX_FLOW]/system_base_power,
        );
        add_component!(sys_DA, tline)
    end
end
