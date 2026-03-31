import Pkg
using ComplexMixturesGUI
dir=@__DIR__
gui(;
    pdbfile="$dir/system.pdb",
    result="$dir/glyc50_results.json"
)
