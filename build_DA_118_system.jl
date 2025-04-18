build_DA = "YES"
build_RT = "NO"

include("Scripts-and-Data/define_buses.jl");
include("Scripts-and-Data/define_lines.jl");
include("Scripts-and-Data/define_gens.jl");
include("Scripts-and-Data/define_time_series.jl");
include("Scripts-and-Data/define_DA_loads.jl");

sys_DA
