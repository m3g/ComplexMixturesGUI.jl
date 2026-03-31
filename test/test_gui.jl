import Pkg
using ComplexMixturesGUI
dir=ComplexMixturesGUI.src_dir
gui(;
    pdbfile="$dir/../test/system.pdb",
    result="$dir/../test/glyc50_results.json"
)
