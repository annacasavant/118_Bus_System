## NREL 118 Bus System 

This folder holds the scripts and data to build the NREL 118 Bus System.  The
scripts included are `build_DA_118_system.jl` and `build_RT_118_system`, which will
build the systemattaching eith Day Ahead (DA) or Real Time (RT) time series data,
respectively. 

Within `Scripts-and-Data` are scripts that each build
the buses, arcs, and time series, as well as loads and generators, separated by
whether DA or RT time series data is being attached to them.

To build the system, run the following code in the Julia REPL:
(come back to this and add more steps on how to activate project)

```julia
include("build_DA_118_system.jl")
```

### Additional data can be found by this
[link](https://nrel-my.sharepoint.com/personal/jlara_nrel_gov/_layouts/15/onedrive.aspx?e=5%3A32113f845c1b4831b939218f2c0cbc8d&sharingv2=true&fromShare=true&CID=8aa3180d%2Dfd9e%2D4a3b%2D9e1d%2D369e05722e0f&id=%2Fpersonal%2Fjlara%5Fnrel%5Fgov%2FDocuments%2F118%20Bus%20Data&FolderCTID=0x012000B41BED7332BCCF40AD8A818F0F8A0D00&view=0&noAuthRedirect=1). 




