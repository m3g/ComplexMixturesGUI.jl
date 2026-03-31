module ComplexMixturesGUI

using WGLMakie
using CairoMakie: CairoMakie
using Bonito
using Bonito: DOM
using ComplexMixtures
using ComplexMixtures: Result,
    SoluteGroup, SolventGroup, ResidueContributions,
    contributions, overview, Overview,
    _set_clims_and_colorscale!
#using PDBTools: Atom, select, read_pdb, eachresidue, residuename
using PDBTools
using Statistics: mean, std

export gui

# Base src directory
const src_dir = @__DIR__

function guess_solvent_selection(atoms::AbstractVector{<:Atom}, result::Result) 
    res = collect(eachresidue(atoms))
    solvent_selection = "water"
    for rs in res
        if length(rs) == result.solvent.natomspermol
            rname = resname(rs)
            if count(r -> resname(r) == rname, res) == result.solvent.nmols
                    solvent_selection = "resname $rname"
                    break
            end
        end
    end
    return solvent_selection
end
guess_solvent_selection(atoms, result) = "water"

# ─────────────────────────────────────────────────────────────────────────
# Native file dialog helper (runs server-side)
# ─────────────────────────────────────────────────────────────────────────

function _pick_file(; title="Select file")
    path = ""
    try
        if Sys.islinux()
            if !isnothing(Sys.which("zenity"))
                path = strip(read(`zenity --file-selection --title=$title`, String))
            elseif !isnothing(Sys.which("kdialog"))
                path = strip(read(`kdialog --getopenfilename . --title $title`, String))
            end
        elseif Sys.isapple()
            path = strip(read(`osascript -e 'POSIX path of (choose file with prompt "Select file")'`, String))
        elseif Sys.iswindows()
            ps = """
            Add-Type -AssemblyName System.Windows.Forms
            \$d = New-Object System.Windows.Forms.OpenFileDialog
            \$d.Title = "$title"
            if (\$d.ShowDialog() -eq 'OK') { \$d.FileName }
            """
            path = strip(read(`powershell -NoProfile -Command $ps`, String))
        end
    catch
    end
    return path
end

function _pick_save_file(; title="Save file")
    path = ""
    try
        if Sys.islinux()
            if !isnothing(Sys.which("zenity"))
                path = strip(read(`zenity --file-selection --save --confirm-overwrite --title=$title`, String))
            elseif !isnothing(Sys.which("kdialog"))
                path = strip(read(`kdialog --getsavefilename . --title $title`, String))
            end
        elseif Sys.isapple()
            path = strip(read(`osascript -e 'POSIX path of (choose file name with prompt "Save file")'`, String))
        elseif Sys.iswindows()
            ps = """
            Add-Type -AssemblyName System.Windows.Forms
            \$d = New-Object System.Windows.Forms.SaveFileDialog
            \$d.Title = "$title"
            \$d.Filter = "JSON files (*.json)|*.json"
            if (\$d.ShowDialog() -eq 'OK') { \$d.FileName }
            """
            path = strip(read(`powershell -NoProfile -Command $ps`, String))
        end
    catch
    end
    return path
end

# ─────────────────────────────────────────────────────────────────────────
# CSS styling
# ─────────────────────────────────────────────────────────────────────────

const _CSS = DOM.style("""
body { font-family: 'Segoe UI', Arial, sans-serif; font-size: 13px; margin: 8px; }
.cm-title { font-size: 16px; font-weight: bold; color: #333; margin: 4px 0 8px 0; text-align: center; letter-spacing: 0.5px; }
.cm-main { display: grid; grid-template-columns: 340px 1fr; gap: 12px; height: calc(100vh - 60px); }
.cm-sidebar { overflow-y: auto; padding: 10px; border: 1px solid #ddd; border-radius: 6px; background: #fafafa; }
.cm-plots { overflow-y: auto; overflow-x: auto; padding: 8px; width: fit-content; }
.cm-section-title { font-weight: bold; font-size: 14px; margin: 10px 0 4px 0; color: #333; }
.cm-row { display: flex; align-items: center; gap: 6px; margin: 3px 0; }
.cm-row label { min-width: 100px; text-align: right; font-size: 12px; color: #555; }
.cm-row-compact { display: flex; align-items: center; gap: 6px; margin: 1px 0 3px 0; padding-left: 6px; }
.cm-row-compact select { max-width: 130px; font-size: 11px; }
.cm-row-compact input { width: 50px; font-size: 11px; }
.cm-row input, .cm-row select { font-size: 12px; padding: 3px 6px; }
.cm-row input[type=text], .cm-row input[type=textfield] { flex: 1; }
.cm-row input[type=number] { width: 70px; }
.cm-required label { color: #b00; font-weight: bold; }
.cm-browse-btn button { padding: 2px 6px; font-size: 11px; min-width: 28px; }
button { font-size: 12px !important; padding: 3px 8px !important; }
input, select, textarea { font-size: 12px !important; }
.cm-grp-list { margin: 4px 0; border: 1px solid #e0e0e0; border-radius: 4px; padding: 4px 8px; overflow-y: auto; background: #fff; }
.cm-grp-item { display: flex; align-items: center; gap: 6px; padding: 2px 0; font-size: 12px; }
.cm-tab2-body { display: flex; gap: 10px; align-items: stretch; }
.cm-grp-panel { width: 220px; flex-shrink: 0; border: 1px solid #ddd; border-radius: 4px; padding: 8px; background: #fafafa; display: flex; flex-direction: column; }
.cm-export-section { margin-top: auto; padding-top: 8px; border-top: 1px solid #ddd; }
.cm-export-field { display: flex; flex-direction: column; gap: 2px; margin: 3px 0; }
.cm-export-field label { color: #555; font-size: 11px; }
.cm-export-field input[type=text], .cm-export-field input[type=textfield] { width: 100%; font-size: 11px !important; box-sizing: border-box; }
.cm-export-field-inline { display: flex; align-items: center; gap: 6px; margin: 3px 0; }
.cm-export-field-inline label { white-space: nowrap; color: #555; font-size: 11px; min-width: 56px; }
.cm-export-field-inline select { flex: 1; font-size: 11px !important; }
.cm-export-btns { display: flex; gap: 4px; margin: 4px 0; flex-wrap: wrap; }
.cm-export-btns button { flex: 1; font-size: 10px !important; padding: 2px 4px !important; }
.cm-grp-panel-title { font-weight: bold; font-size: 12px; color: #333; margin-bottom: 4px; }
.cm-comp-tabs { display: flex; gap: 0; margin-bottom: 6px; border-bottom: 2px solid #ccc; width: fit-content; }
.cm-comp-tab button { font-size: 11px !important; padding: 3px 8px !important; border: 1px solid #ccc; border-bottom: none; border-radius: 3px 3px 0 0; background: #f0f0f0; cursor: pointer; margin-right: 2px; width: fit-content !important; }
.cm-comp-tab.active button { background: #3970d1 !important; color: white !important; font-weight: bold; border-color: #3970d1; }
.cm-fig-wrap { display: flex; flex-direction: column; }
.cm-fig-row { display: flex; align-items: stretch; }
.cm-ylabel { writing-mode: vertical-rl; transform: rotate(180deg); font-size: 12px; color: #444; text-align: center; padding: 0 3px; white-space: nowrap; }
.cm-xlabel { text-align: center; font-size: 12px; color: #444; margin: 1px 0 3px 0; }
.cm-plot-title { text-align: center; font-size: 14px; font-weight: bold; color: #222; margin: 6px 0 1px 0; }
.cm-row-left label { min-width: auto !important; text-align: left !important; font-weight: normal; }
.cm-tabs { display: flex; gap: 4px; margin-bottom: 0px; }
.cm-tab-btn { padding: 6px 16px; border: 1px solid #ccc; border-radius: 4px 4px 0 0;
              cursor: pointer; background: #eee; font-size: 12px; border-bottom: none; user-select: none; }
.cm-tab-btn.active { background: #3970d1; color: white; font-weight: bold; }
.cm-tab-content { display: none; border: 1px solid #ccc; border-radius: 0 4px 4px 4px; padding: 8px; background: #fff; }
.cm-tab-content.active { display: block; }
.cm-status { font-size: 11px; color: #888; padding: 4px 8px; border-top: 1px solid #ddd; }
.cm-toggle-row { display: flex; align-items: center; justify-content: center; gap: 10px; margin: 3px 0; font-size: 11px; color: #777; }
.cm-advanced-sep { border: none; border-top: 1px solid #e0e0e0; margin: 6px 0 4px 0; }
.cm-lims-row { display: flex; align-items: center; gap: 3px; margin: 3px 0; font-size: 10px; flex-wrap: wrap; }
.cm-lims-row span { color: #666; font-size: 10px; }
.cm-lims-row input[type=number] { width: 50px; font-size: 10px; padding: 1px 3px; }
.cm-lims-row button { font-size: 10px; padding: 2px 6px; }
.cm-lims-grid { display: grid; grid-template-columns: auto 1fr auto 1fr; align-items: center; gap: 3px; margin: 3px 0; font-size: 10px; }
.cm-lims-grid span { color: #666; font-size: 10px; white-space: nowrap; }
.cm-lims-grid input { width: 100% !important; min-width: 0 !important; font-size: 10px !important; padding: 1px 3px !important; box-sizing: border-box !important; }
.cm-overview { font-family: 'Cascadia Mono', 'Consolas', monospace; font-size: 11px; white-space: pre-wrap; padding: 6px;
               border: 1px solid #ddd; border-radius: 4px; background: #fff; max-height: 400px; overflow-y: auto; }
.cm-overview table { border-collapse: collapse; width: 100%; font-size: 11px; }
.cm-overview td { padding: 2px 6px; }
.cm-overview td:first-child { color: #555; text-align: right; white-space: nowrap; }
.cm-overview td:last-child { font-weight: 500; }
.cm-overview .cm-ov-section { font-weight: bold; font-size: 12px; color: #333; padding: 6px 0 2px 0; }
.cm-sidebar-tabs { display: flex; gap: 2px; margin-bottom: 4px; }
.cm-sidebar-tab { padding: 4px 12px; border: 1px solid #ccc; border-radius: 4px 4px 0 0;
                  cursor: pointer; background: #eee; font-size: 11px; border-bottom: none; user-select: none; }
.cm-sidebar-tab.active { background: #555; color: white; font-weight: bold; }
.cm-sidebar-content { display: none; }
.cm-sidebar-content.active { display: block; }
""")

# ─────────────────────────────────────────────────────────────────────────
# Format overview as HTML
# ─────────────────────────────────────────────────────────────────────────

function _overview_text(R::Result)
    ov = overview(R)
    fmt(x) = string(round(x; sigdigits=6))
    ifar = trunc(Int, ov.R.nbins - 1.0 / ov.R.files[1].options.binstep)
    lr_mddf_mean = fmt(mean(ov.R.mddf[ifar:ov.R.nbins]))
    lr_mddf_std = fmt(std(ov.R.mddf[ifar:ov.R.nbins]))
    lr_rdf_mean = fmt(mean(ov.R.rdf[ifar:ov.R.nbins]))
    lr_rdf_std = fmt(std(ov.R.rdf[ifar:ov.R.nbins]))
    bulk_str = ComplexMixtures._bulk_range_from_R(ov.R)
    files_str = join(
        ["  $(normpath(ov.R.files[i].filename)) (w=$(ov.R.weights[i]))" for i in eachindex(ov.R.files)],
        "\n"
    )
    return """
Solvent
  Concentration:      $(fmt(ov.density.solvent)) mol/L
  Molar volume:       $(fmt(ov.solvent_molar_volume)) cm³/mol
  Bulk concentration: $(fmt(ov.density.solvent_bulk)) mol/L
  Bulk molar volume:  $(fmt(ov.solvent_molar_volume_bulk)) cm³/mol

Solute
  Concentration:      $(fmt(ov.density.solute)) mol/L
  Partial molar vol.: $(fmt(ov.solute_molar_volume)) cm³/mol

System
  Bulk range:         $(bulk_str)
  Domain molar vol.:  $(fmt(ov.domain_molar_volume)) cm³/mol
  Auto-correlation:   $(ov.R.autocorrelation)

Convergence
  Long-range MDDF:    $(lr_mddf_mean) ± $(lr_mddf_std)
  Long-range RDF:     $(lr_rdf_mean) ± $(lr_rdf_std)

Trajectory files
$(files_str)
"""
end

# ─────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────

"""
    ComplexMixtures.gui(; pdbfile=nothing, result=nothing, port=9384)

Launch the Bonito/WGLMakie web-based interface for ComplexMixtures analysis.
Opens a browser at `http://localhost:\$port`.
"""
function gui(;
    pdbfile::Union{<:AbstractString,Nothing}=nothing,
    result::Union{<:AbstractString,Nothing}=nothing,
    port::Int=9384,
)
    app = App() do session::Bonito.Session
        # ── State ──────────────────────────────────────────────────────
        result_obs = Observable{Union{Nothing,Result}}(nothing)
        atoms_obs = Observable{Union{Nothing,Vector{Atom}}}(nothing)
        status_obs = Observable("Ready")
        overview_obs = Observable("No results loaded.")

        # (preload happens after all callbacks are defined, see below)

        # ══════════════════════════════════════════════════════════════
        # LEFT PANEL
        # ══════════════════════════════════════════════════════════════

        tf_pdb  = Bonito.TextField(isnothing(pdbfile) ? "" : pdbfile)
        btn_browse_pdb  = Bonito.Button("📂")
        tf_json = Bonito.TextField(isnothing(result) ? "" : result)
        btn_browse_json = Bonito.Button("📂")
        btn_load = Bonito.Button("Load")

        # Solute / solvent selection fields (also used in contributions tabs)
        _initial_solvent = isnothing(result_obs[]) ? "water" :
            guess_solvent_selection(something(atoms_obs[], Atom[]), result_obs[])
        tf_comp_sol = Bonito.TextField("protein")
        tf_comp_slv = Bonito.TextField(_initial_solvent)

        sidebar = DOM.div(class="cm-sidebar",
            DOM.div(class="cm-section-title", "Input Files"),
            DOM.div(class="cm-row cm-required", DOM.label("PDB / mmCIF:"), tf_pdb, DOM.div(class="cm-browse-btn", btn_browse_pdb)),
            DOM.div(class="cm-row cm-required", DOM.label("Results JSON:"), tf_json, DOM.div(class="cm-browse-btn", btn_browse_json)),
            DOM.div(style="text-align:center; margin: 6px 0;", btn_load),
            DOM.div(class="cm-section-title", "Selections"),
            DOM.div(class="cm-row", DOM.label("Solute:"), tf_comp_sol),
            DOM.div(class="cm-row", DOM.label("Solvent:"), tf_comp_slv),
            DOM.div(class="cm-section-title", "Result Overview"),
            DOM.div(class="cm-overview", overview_obs),
        )

        # ══════════════════════════════════════════════════════════════
        # RIGHT PANEL — plots with tabs
        # ══════════════════════════════════════════════════════════════

        # ── Tab 1: MDDF & KB ──────────────────────────────────────────
        fig1_mddf = Figure(; size=(900, 295))
        ax_mddf = Axis(fig1_mddf[1, 1]; xticklabelsize=11, yticklabelsize=11)
        fig1_kb = Figure(; size=(900, 295))
        ax_kb = Axis(fig1_kb[1, 1]; xticklabelsize=11, yticklabelsize=11)

        # Tab 1 limits and export
        tf_mddf_xmin  = Bonito.NumberInput(0.0)
        tf_mddf_xmax  = Bonito.NumberInput(10.0)
        tf_mddf_ymin  = Bonito.NumberInput(0.0)
        tf_mddf_ymax  = Bonito.NumberInput(5.0)
        tf_kb_xmin    = Bonito.NumberInput(0.0)
        tf_kb_xmax    = Bonito.NumberInput(10.0)
        tf_kb_ymin    = Bonito.NumberInput(-1.0)
        tf_kb_ymax    = Bonito.NumberInput(1.0)
        btn_tab1_lims = Bonito.Button("Apply")
        dd_export_fmt1   = Bonito.Dropdown(["svg", "pdf", "png"])
        btn_export_mddf1 = Bonito.Button("Export MDDF plot")
        btn_export_kb1   = Bonito.Button("Export KB plot")
        btn_export_csv1  = Bonito.Button("Export data (CSV)")
        last_tab1_data   = Observable{Any}(nothing)

        # ── Tab 2 & 3: Group Contributions (Solute / Solvent) ────────────
        MAX_GROUPS = 10

        # Solute group tab figures
        fig_sol_mddf = Figure(; size=(900, 295))
        ax_sol_mddf = Axis(fig_sol_mddf[1, 1]; xticklabelsize=11, yticklabelsize=11)
        fig_sol_cn = Figure(; size=(900, 295))
        ax_sol_cn = Axis(fig_sol_cn[1, 1]; xticklabelsize=11, yticklabelsize=11)

        # Solvent group tab figures
        fig_slv_mddf = Figure(; size=(900, 295))
        ax_slv_mddf = Axis(fig_slv_mddf[1, 1]; xticklabelsize=11, yticklabelsize=11)
        fig_slv_cn = Figure(; size=(900, 295))
        ax_slv_cn = Axis(fig_slv_cn[1, 1]; xticklabelsize=11, yticklabelsize=11)

        # Solute group state
        tf_newgrp_sol = Bonito.TextField("resname ARG LYS")
        btn_addgrp_sol = Bonito.Button("Add")
        btn_rmgrp_sol = Bonito.Button("Remove unchecked")
        grp_names_sol  = [Observable("") for _ in 1:MAX_GROUPS]
        grp_labels_sol = [Observable("") for _ in 1:MAX_GROUPS]
        grp_checks_sol = [Bonito.Checkbox(true) for _ in 1:MAX_GROUPS]
        grp_active_sol = Observable(0)
        grp_total_sol = Bonito.Checkbox(true)

        # Solvent group state
        tf_newgrp_slv = Bonito.TextField("element O")
        btn_addgrp_slv = Bonito.Button("Add")
        btn_rmgrp_slv = Bonito.Button("Remove unchecked")
        grp_names_slv  = [Observable("") for _ in 1:MAX_GROUPS]
        grp_labels_slv = [Observable("") for _ in 1:MAX_GROUPS]
        grp_checks_slv = [Bonito.Checkbox(true) for _ in 1:MAX_GROUPS]
        grp_active_slv = Observable(0)
        grp_total_slv = Bonito.Checkbox(true)

        checklist_sol_dom = map(grp_active_sol) do n
            rows = Any[DOM.div(class="cm-grp-item", grp_total_sol, DOM.span("Total MDDF"))]
            for i in 1:n
                push!(rows, DOM.div(class="cm-grp-item", grp_checks_sol[i], DOM.span(grp_labels_sol[i][])))
            end
            DOM.div(class="cm-grp-list", rows...)
        end

        checklist_slv_dom = map(grp_active_slv) do n
            rows = Any[DOM.div(class="cm-grp-item", grp_total_slv, DOM.span("Total MDDF"))]
            for i in 1:n
                push!(rows, DOM.div(class="cm-grp-item", grp_checks_slv[i], DOM.span(grp_labels_slv[i][])))
            end
            DOM.div(class="cm-grp-list", rows...)
        end

        # Group limits — all separate per tab (DOM nodes cannot be shared)
        tf_sol_xmin      = Bonito.NumberInput(0.0)
        tf_sol_xmax      = Bonito.NumberInput(10.0)
        tf_sol_mddf_ymin = Bonito.NumberInput(0.0)
        tf_sol_mddf_ymax = Bonito.NumberInput(5.0)
        tf_sol_cn_ymin   = Bonito.NumberInput(0.0)
        tf_sol_cn_ymax   = Bonito.NumberInput(5.0)
        tf_slv_xmin      = Bonito.NumberInput(0.0)
        tf_slv_xmax      = Bonito.NumberInput(10.0)
        tf_slv_mddf_ymin = Bonito.NumberInput(0.0)
        tf_slv_mddf_ymax = Bonito.NumberInput(5.0)
        tf_slv_cn_ymin   = Bonito.NumberInput(0.0)
        tf_slv_cn_ymax   = Bonito.NumberInput(5.0)
        btn_grp_lims_sol = Bonito.Button("Apply")
        btn_grp_lims_slv = Bonito.Button("Apply")

        # Export controls - Solute
        dd_export_fmt_sol   = Bonito.Dropdown(["svg", "pdf", "png"])
        btn_export_mddf_sol = Bonito.Button("Export MDDF plot")
        btn_export_cn_sol   = Bonito.Button("Export CN plot")
        btn_export_csv_sol  = Bonito.Button("Export data (CSV)")
        last_sol_data = Observable{Any}(nothing)

        # Export controls - Solvent
        dd_export_fmt_slv   = Bonito.Dropdown(["svg", "pdf", "png"])
        btn_export_mddf_slv = Bonito.Button("Export MDDF plot")
        btn_export_cn_slv   = Bonito.Button("Export CN plot")
        btn_export_csv_slv  = Bonito.Button("Export data (CSV)")
        last_slv_data = Observable{Any}(nothing)

        tab_sol_body = DOM.div(class="cm-tab2-body",
            DOM.div(
                DOM.div(class="cm-fig-wrap",
                    DOM.div(class="cm-plot-title", "Solute MDDF Group Contributions"),
                    DOM.div(class="cm-fig-row",
                        DOM.span(class="cm-ylabel", "MDDF(r)"),
                        fig_sol_mddf,
                    ),
                ),
                DOM.div(class="cm-fig-wrap",
                    DOM.div(class="cm-plot-title", "Solute Coord. Number Group Contributions"),
                    DOM.div(class="cm-fig-row",
                        DOM.span(class="cm-ylabel", "Coordination number"),
                        fig_sol_cn,
                    ),
                ),
                DOM.div(class="cm-xlabel", "r (Angstrom)"),
            ),
            DOM.div(class="cm-grp-panel",
                DOM.div(class="cm-grp-panel-title", "Groups"),
                DOM.div(class="cm-lims-row", tf_newgrp_sol, btn_addgrp_sol),
                checklist_sol_dom,
                DOM.div(style="margin: 4px 0;", btn_rmgrp_sol),
                DOM.div(class="cm-export-section",
                    DOM.div(class="cm-grp-panel-title", "Limits"),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("x:"), tf_sol_xmin, DOM.span("–"), tf_sol_xmax),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("MDDF y:"), tf_sol_mddf_ymin, DOM.span("–"), tf_sol_mddf_ymax),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("CN y:"), tf_sol_cn_ymin, DOM.span("–"), tf_sol_cn_ymax),
                    DOM.div(class="cm-export-btns", btn_grp_lims_sol),
                    DOM.hr(class="cm-advanced-sep"),
                    DOM.div(class="cm-grp-panel-title", "Export"),
                    DOM.div(class="cm-export-field-inline", DOM.label("Format:"), dd_export_fmt_sol),
                    DOM.div(class="cm-export-btns", btn_export_mddf_sol, btn_export_cn_sol),
                    DOM.div(class="cm-export-btns", btn_export_csv_sol),
                ),
            ),
        )

        tab_slv_body = DOM.div(class="cm-tab2-body",
            DOM.div(
                DOM.div(class="cm-fig-wrap",
                    DOM.div(class="cm-plot-title", "Solvent MDDF Group Contributions"),
                    DOM.div(class="cm-fig-row",
                        DOM.span(class="cm-ylabel", "MDDF(r)"),
                        fig_slv_mddf,
                    ),
                ),
                DOM.div(class="cm-fig-wrap",
                    DOM.div(class="cm-plot-title", "Solvent Coord. Number Group Contributions"),
                    DOM.div(class="cm-fig-row",
                        DOM.span(class="cm-ylabel", "Coordination number"),
                        fig_slv_cn,
                    ),
                ),
                DOM.div(class="cm-xlabel", "r (Angstrom)"),
            ),
            DOM.div(class="cm-grp-panel",
                DOM.div(class="cm-grp-panel-title", "Groups"),
                DOM.div(class="cm-lims-row", tf_newgrp_slv, btn_addgrp_slv),
                checklist_slv_dom,
                DOM.div(style="margin: 4px 0;", btn_rmgrp_slv),
                DOM.div(class="cm-export-section",
                    DOM.div(class="cm-grp-panel-title", "Limits"),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("x:"), tf_slv_xmin, DOM.span("–"), tf_slv_xmax),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("MDDF y:"), tf_slv_mddf_ymin, DOM.span("–"), tf_slv_mddf_ymax),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("CN y:"), tf_slv_cn_ymin, DOM.span("–"), tf_slv_cn_ymax),
                    DOM.div(class="cm-export-btns", btn_grp_lims_slv),
                    DOM.hr(class="cm-advanced-sep"),
                    DOM.div(class="cm-grp-panel-title", "Export"),
                    DOM.div(class="cm-export-field-inline", DOM.label("Format:"), dd_export_fmt_slv),
                    DOM.div(class="cm-export-btns", btn_export_mddf_slv, btn_export_cn_slv),
                    DOM.div(class="cm-export-btns", btn_export_csv_slv),
                ),
            ),
        )

        # ── Tab 3: Residue Contributions ──────────────────────────────
        fig3_mddf = Figure(; size=(900, 295))
        ax_rc_mddf = Axis(fig3_mddf[1, 1]; xticklabelsize=9, yticklabelsize=11)
        fig3_cn = Figure(; size=(900, 295))
        ax_rc_cn = Axis(fig3_cn[1, 1]; xticklabelsize=9, yticklabelsize=11)
        tf_rc_sel = Bonito.TextField("protein")
        btn_rc_plot = Bonito.Button("Plot")

        btn_export_csv_rc  = Bonito.Button("Export data (CSV)")
        dd_export_fmt_rc   = Bonito.Dropdown(["svg", "pdf", "png"])
        btn_export_mddf_rc = Bonito.Button("Export MDDF plot")
        btn_export_cn_rc   = Bonito.Button("Export CN plot")
        tf_rc_xmin = Bonito.TextField("0")
        tf_rc_xmax = Bonito.TextField("100")
        tf_rc_ymin = Bonito.NumberInput(1.5)
        tf_rc_ymax = Bonito.NumberInput(3.5)
        btn_rc_lims = Bonito.Button("Apply")
        last_rc_data = Observable{Any}(nothing)

        tab3_body = DOM.div(class="cm-tab2-body",
            DOM.div(
                DOM.div(class="cm-fig-wrap",
                    DOM.div(class="cm-plot-title", "Residue Contributions to MDDF"),
                    DOM.div(class="cm-fig-row",
                        DOM.span(class="cm-ylabel", "r (Angstrom)"),
                        fig3_mddf,
                    ),
                ),
                DOM.div(class="cm-fig-wrap",
                    DOM.div(class="cm-plot-title", "Residue Contributions to Coordination Number"),
                    DOM.div(class="cm-fig-row",
                        DOM.span(class="cm-ylabel", "r (Angstrom)"),
                        fig3_cn,
                    ),
                ),
                DOM.div(class="cm-xlabel", "Residue"),
            ),
            DOM.div(class="cm-grp-panel",
                DOM.div(class="cm-row cm-row-left", DOM.label("Selection:"), tf_rc_sel),
                DOM.div(style="text-align: center; margin: 4px 0;", btn_rc_plot),
                DOM.div(class="cm-export-section",
                    DOM.div(class="cm-grp-panel-title", "Limits"),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("x:"), tf_rc_xmin, DOM.span("–"), tf_rc_xmax),
                    DOM.div(class="cm-lims-grid",
                        DOM.span("y:"), tf_rc_ymin, DOM.span("–"), tf_rc_ymax),
                    DOM.div(class="cm-export-btns", btn_rc_lims),
                    DOM.hr(class="cm-advanced-sep"),
                    DOM.div(class="cm-grp-panel-title", "Export"),
                    DOM.div(class="cm-export-field-inline", DOM.label("Format:"), dd_export_fmt_rc),
                    DOM.div(class="cm-export-btns", btn_export_mddf_rc, btn_export_cn_rc),
                    DOM.div(class="cm-export-btns", btn_export_csv_rc),
                ),
            ),
        )

        # ── Plot tabs JS switching ────────────────────────────────────
        tab_switch_js = DOM.script("""
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                var btns = document.querySelectorAll('.cm-tab-btn');
                var tabs = document.querySelectorAll('.cm-tab-content');
                btns.forEach(function(b, i) {
                    b.addEventListener('click', function() {
                        btns.forEach(function(bb) { bb.classList.remove('active'); });
                        tabs.forEach(function(tt) { tt.classList.remove('active'); });
                        b.classList.add('active');
                        tabs[i].classList.add('active');
                    });
                });
            }, 500);
        });
        """)

        plots_panel = DOM.div(class="cm-plots",
            DOM.div(class="cm-tabs",
                DOM.div(class="cm-tab-btn active", "MDDF & KB"),
                DOM.div(class="cm-tab-btn", "Solute group contributions"),
                DOM.div(class="cm-tab-btn", "Solvent group contributions"),
                DOM.div(class="cm-tab-btn", "Residue Contributions"),
            ),
            DOM.div(class="cm-tab-content active",
                DOM.div(class="cm-tab2-body",
                    DOM.div(
                        DOM.div(class="cm-fig-wrap",
                            DOM.div(class="cm-plot-title", "MDDF"),
                            DOM.div(class="cm-fig-row",
                                DOM.span(class="cm-ylabel", "MDDF(r)"),
                                fig1_mddf,
                            ),
                        ),
                        DOM.div(class="cm-fig-wrap",
                            DOM.div(class="cm-plot-title", "Kirkwood-Buff Integral"),
                            DOM.div(class="cm-fig-row",
                                DOM.span(class="cm-ylabel", "KB (L/mol)"),
                                fig1_kb,
                            ),
                        ),
                        DOM.div(class="cm-xlabel", "r (Angstrom)"),
                    ),
                    DOM.div(class="cm-grp-panel",
                        DOM.div(class="cm-export-section",
                            DOM.div(class="cm-grp-panel-title", "Limits"),
                            DOM.div(class="cm-lims-grid",
                                DOM.span("MDDF x:"), tf_mddf_xmin, DOM.span("–"), tf_mddf_xmax),
                            DOM.div(class="cm-lims-grid",
                                DOM.span("MDDF y:"), tf_mddf_ymin, DOM.span("–"), tf_mddf_ymax),
                            DOM.div(class="cm-lims-grid",
                                DOM.span("KB x:"), tf_kb_xmin, DOM.span("–"), tf_kb_xmax),
                            DOM.div(class="cm-lims-grid",
                                DOM.span("KB y:"), tf_kb_ymin, DOM.span("–"), tf_kb_ymax),
                            DOM.div(class="cm-export-btns", btn_tab1_lims),
                            DOM.hr(class="cm-advanced-sep"),
                            DOM.div(class="cm-grp-panel-title", "Export"),
                            DOM.div(class="cm-export-field-inline", DOM.label("Format:"), dd_export_fmt1),
                            DOM.div(class="cm-export-btns", btn_export_mddf1, btn_export_kb1),
                            DOM.div(class="cm-export-btns", btn_export_csv1),
                        ),
                    ),
                ),
            ),
            DOM.div(class="cm-tab-content", tab_sol_body),
            DOM.div(class="cm-tab-content", tab_slv_body),
            DOM.div(class="cm-tab-content", tab3_body),
            tab_switch_js,
        )

        status_bar = DOM.div(class="cm-status", status_obs)

        # ══════════════════════════════════════════════════════════════
        # CALLBACKS
        # ══════════════════════════════════════════════════════════════

        # ── Browse buttons ─────────────────────────────────────────────
        on(btn_browse_pdb.value) do _
            path = _pick_file(; title="Select PDB / mmCIF file")
            if !isempty(path)
                tf_pdb.value[] = path
            end
        end
        on(btn_browse_json.value) do _
            path = _pick_file(; title="Select JSON result file")
            isempty(path) || (tf_json.value[] = path)
        end

        # ── Group management ───────────────────────────────────────────
        function _grp_label(sel, comp_sel, at)
            if at === nothing
                return sel
            end
            combined = isempty(strip(comp_sel)) ? sel : "($comp_sel) and ($sel)"
            n_atoms = try length(select(at, combined)) catch; -1 end
            n_atoms < 0 ? sel : "$sel ($n_atoms atoms)"
        end

        on(btn_addgrp_sol.value) do _
            sel = strip(String(tf_newgrp_sol.value[]))
            isempty(sel) && return
            n = grp_active_sol[]
            n >= MAX_GROUPS && (status_obs[] = "Maximum $MAX_GROUPS groups reached"; return)
            for i in 1:n; grp_names_sol[i][] == sel && return; end
            grp_names_sol[n + 1][] = sel
            grp_labels_sol[n + 1][] = _grp_label(sel, String(tf_comp_sol.value[]), atoms_obs[])
            grp_checks_sol[n + 1].value[] = true
            grp_active_sol[] = n + 1
        end
        on(btn_rmgrp_sol.value) do _
            n = grp_active_sol[]
            kept_names = String[]; kept_labels = String[]
            for i in 1:n
                if grp_checks_sol[i].value[]
                    push!(kept_names, grp_names_sol[i][])
                    push!(kept_labels, grp_labels_sol[i][])
                end
            end
            for i in eachindex(kept_names)
                grp_names_sol[i][] = kept_names[i]
                grp_labels_sol[i][] = kept_labels[i]
                grp_checks_sol[i].value[] = true
            end
            grp_active_sol[] = length(kept_names)
        end
        on(btn_addgrp_slv.value) do _
            sel = strip(String(tf_newgrp_slv.value[]))
            isempty(sel) && return
            n = grp_active_slv[]
            n >= MAX_GROUPS && (status_obs[] = "Maximum $MAX_GROUPS groups reached"; return)
            for i in 1:n; grp_names_slv[i][] == sel && return; end
            grp_names_slv[n + 1][] = sel
            grp_labels_slv[n + 1][] = _grp_label(sel, String(tf_comp_slv.value[]), atoms_obs[])
            grp_checks_slv[n + 1].value[] = true
            grp_active_slv[] = n + 1
        end
        on(btn_rmgrp_slv.value) do _
            n = grp_active_slv[]
            kept_names = String[]; kept_labels = String[]
            for i in 1:n
                if grp_checks_slv[i].value[]
                    push!(kept_names, grp_names_slv[i][])
                    push!(kept_labels, grp_labels_slv[i][])
                end
            end
            for i in eachindex(kept_names)
                grp_names_slv[i][] = kept_names[i]
                grp_labels_slv[i][] = kept_labels[i]
                grp_checks_slv[i].value[] = true
            end
            grp_active_slv[] = length(kept_names)
        end

        # ── Full UI reset (called on every load) ──────────────────────
        function _reset_ui!(R)
            # ── Tab 1: MDDF & KB ──────────────────────────────────────
            empty!(ax_mddf); empty!(ax_kb)
            for c in copy(fig1_mddf.content); c isa Legend && delete!(c); end
            for c in copy(fig1_kb.content);   c isa Legend && delete!(c); end
            lines!(ax_mddf, R.d, R.mddf; color=:dodgerblue, linewidth=1.5, label="MDDF")
            hlines!(ax_mddf, [1.0]; color=:gray60, linestyle=:dash)
            axislegend(ax_mddf; position=:rt, labelsize=10)
            lines!(ax_kb, R.d, R.kb ./ 1000; color=:orangered, linewidth=1.5, label="KB integral")
            axislegend(ax_kb; position=:rt, labelsize=10)
            last_tab1_data[] = (d=copy(R.d), mddf=copy(R.mddf), kb=copy(R.kb ./ 1000))
            try
                overview_obs[] = _overview_text(R)
            catch
                overview_obs[] = "Overview unavailable."
            end

            # ── Tab 2 & 3: clear group contribution plots and group lists ──
            for ax in (ax_sol_mddf, ax_sol_cn, ax_slv_mddf, ax_slv_cn)
                empty!(ax)
            end
            for fig in (fig_sol_mddf, fig_sol_cn, fig_slv_mddf, fig_slv_cn)
                for c in copy(fig.content); c isa Legend && delete!(c); end
            end
            grp_active_sol[] = 0
            grp_active_slv[] = 0
            for i in 1:MAX_GROUPS
                grp_names_sol[i][]  = ""; grp_labels_sol[i][] = ""
                grp_names_slv[i][]  = ""; grp_labels_slv[i][] = ""
                grp_checks_sol[i].value[] = true
                grp_checks_slv[i].value[] = true
            end
            last_sol_data[] = nothing
            last_slv_data[] = nothing

            # ── Tab 4: clear residue contribution plots ────────────────
            empty!(ax_rc_mddf); empty!(ax_rc_cn)
            last_rc_data[] = nothing
        end

        # ── Load JSON ──────────────────────────────────────────────────
        on(btn_load.value) do _
            json_path = strip(String(tf_json.value[]))
            pdb_path  = strip(String(tf_pdb.value[]))
            if isempty(json_path) || !isfile(json_path)
                status_obs[] = "JSON file not found: $json_path"; return
            end
            if isempty(pdb_path) || !isfile(pdb_path)
                status_obs[] = "PDB file not found: $pdb_path"; return
            end
            status_obs[] = "Loading…"
            try
                R  = ComplexMixtures.load(json_path)
                at = read_pdb(pdb_path)
                slv_sel = guess_solvent_selection(at, R)
                atoms_obs[] = at
                result_obs[] = R
                tf_comp_slv.value[] = slv_sel
                _reset_ui!(R)
                status_obs[] = "Loaded: $json_path"
            catch e
                status_obs[] = "Error: $(sprint(showerror, e))"
            end
        end

        # ── Tab 1: limits ─────────────────────────────────────────────
        on(btn_tab1_lims.value) do _
            xlims!(ax_mddf, Float64(tf_mddf_xmin.value[]), Float64(tf_mddf_xmax.value[]))
            ylims!(ax_mddf, Float64(tf_mddf_ymin.value[]), Float64(tf_mddf_ymax.value[]))
            xlims!(ax_kb,   Float64(tf_kb_xmin.value[]),   Float64(tf_kb_xmax.value[]))
            ylims!(ax_kb,   Float64(tf_kb_ymin.value[]),   Float64(tf_kb_ymax.value[]))
        end

        # ── Tab 2/3: group contributions ──────────────────────────────
        palette = [:orangered, :green3, :purple, :goldenrod, :deeppink,
                   :teal, :slateblue, :sienna, :cyan4, :olive]

        function _update_sol_grp_plots!()
            R = result_obs[]; R === nothing && return
            at = atoms_obs[]; at === nothing && return
            comp_sel = String(tf_comp_sol.value[])
            n = grp_active_sol[]
            active_sels = String[]
            for i in 1:n; grp_checks_sol[i].value[] && push!(active_sels, grp_names_sol[i][]); end
            group_labels = String[]; mddf_curves = Vector{Float64}[]; cn_curves = Vector{Float64}[]
            for sel in active_sels
                combined_sel = isempty(strip(comp_sel)) ? sel : "($comp_sel) and ($sel)"
                local sel_atoms
                try; sel_atoms = select(at, combined_sel)
                catch e; status_obs[] = "Error in selection '$combined_sel': $(sprint(showerror, e))"; return; end
                isempty(sel_atoms) && (status_obs[] = "Selection '$combined_sel' matched no atoms"; return)
                grp = SoluteGroup(sel_atoms)
                push!(group_labels, sel)
                push!(mddf_curves, contributions(R, grp; type=:mddf))
                push!(cn_curves, contributions(R, grp; type=:coordination_number))
            end
            empty!(ax_sol_mddf)
            for c in copy(fig_sol_mddf.content); c isa Legend && delete!(c); end
            if grp_total_sol.value[]
                lines!(ax_sol_mddf, R.d, R.mddf; color=:dodgerblue, linewidth=2, label="Total MDDF")
                hlines!(ax_sol_mddf, [1.0]; color=:gray60, linestyle=:dash)
            end
            for (k, lab) in enumerate(group_labels)
                lines!(ax_sol_mddf, R.d, mddf_curves[k]; color=palette[mod1(k, length(palette))], linewidth=1.5, label=lab)
            end
            axislegend(ax_sol_mddf; position=:rt, labelsize=9)
            empty!(ax_sol_cn)
            for c in copy(fig_sol_cn.content); c isa Legend && delete!(c); end
            if grp_total_sol.value[]
                lines!(ax_sol_cn, R.d, R.coordination_number; color=:dodgerblue, linewidth=2, label="Total")
            end
            for (k, lab) in enumerate(group_labels)
                lines!(ax_sol_cn, R.d, cn_curves[k]; color=palette[mod1(k, length(palette))], linewidth=1.5, label=lab)
            end
            axislegend(ax_sol_cn; position=:lt, labelsize=9)
            last_sol_data[] = (
                d            = copy(R.d),
                total_mddf   = grp_total_sol.value[] ? copy(R.mddf) : nothing,
                total_cn     = grp_total_sol.value[] ? copy(R.coordination_number) : nothing,
                group_labels = copy(group_labels),
                mddf_curves  = copy(mddf_curves),
                cn_curves    = copy(cn_curves),
            )
            status_obs[] = "Solute group contributions updated ($(length(group_labels)) groups)"
        end

        function _update_slv_grp_plots!()
            R = result_obs[]; R === nothing && return
            at = atoms_obs[]; at === nothing && return
            comp_sel = String(tf_comp_slv.value[])
            n = grp_active_slv[]
            active_sels = String[]
            for i in 1:n; grp_checks_slv[i].value[] && push!(active_sels, grp_names_slv[i][]); end
            group_labels = String[]; mddf_curves = Vector{Float64}[]; cn_curves = Vector{Float64}[]
            for sel in active_sels
                combined_sel = isempty(strip(comp_sel)) ? sel : "($comp_sel) and ($sel)"
                local sel_atoms
                try; sel_atoms = select(at, combined_sel)
                catch e; status_obs[] = "Error in selection '$combined_sel': $(sprint(showerror, e))"; return; end
                isempty(sel_atoms) && (status_obs[] = "Selection '$combined_sel' matched no atoms"; return)
                grp = SolventGroup(sel_atoms)
                push!(group_labels, sel)
                push!(mddf_curves, contributions(R, grp; type=:mddf))
                push!(cn_curves, contributions(R, grp; type=:coordination_number))
            end
            empty!(ax_slv_mddf)
            for c in copy(fig_slv_mddf.content); c isa Legend && delete!(c); end
            if grp_total_slv.value[]
                lines!(ax_slv_mddf, R.d, R.mddf; color=:dodgerblue, linewidth=2, label="Total MDDF")
                hlines!(ax_slv_mddf, [1.0]; color=:gray60, linestyle=:dash)
            end
            for (k, lab) in enumerate(group_labels)
                lines!(ax_slv_mddf, R.d, mddf_curves[k]; color=palette[mod1(k, length(palette))], linewidth=1.5, label=lab)
            end
            axislegend(ax_slv_mddf; position=:rt, labelsize=9)
            empty!(ax_slv_cn)
            for c in copy(fig_slv_cn.content); c isa Legend && delete!(c); end
            if grp_total_slv.value[]
                lines!(ax_slv_cn, R.d, R.coordination_number; color=:dodgerblue, linewidth=2, label="Total")
            end
            for (k, lab) in enumerate(group_labels)
                lines!(ax_slv_cn, R.d, cn_curves[k]; color=palette[mod1(k, length(palette))], linewidth=1.5, label=lab)
            end
            axislegend(ax_slv_cn; position=:lt, labelsize=9)
            last_slv_data[] = (
                d            = copy(R.d),
                total_mddf   = grp_total_slv.value[] ? copy(R.mddf) : nothing,
                total_cn     = grp_total_slv.value[] ? copy(R.coordination_number) : nothing,
                group_labels = copy(group_labels),
                mddf_curves  = copy(mddf_curves),
                cn_curves    = copy(cn_curves),
            )
            status_obs[] = "Solvent group contributions updated ($(length(group_labels)) groups)"
        end

        on(grp_total_sol.value) do _; _update_sol_grp_plots!(); end
        on(grp_total_slv.value) do _; _update_slv_grp_plots!(); end
        on(grp_active_sol) do n; n > 0 && _update_sol_grp_plots!(); end
        on(grp_active_slv) do n; n > 0 && _update_slv_grp_plots!(); end
        for i in 1:MAX_GROUPS
            on(grp_checks_sol[i].value) do _; i <= grp_active_sol[] && _update_sol_grp_plots!(); end
            on(grp_checks_slv[i].value) do _; i <= grp_active_slv[] && _update_slv_grp_plots!(); end
        end
        on(tf_comp_sol.value) do _; grp_active_sol[] > 0 && _update_sol_grp_plots!(); end
        on(tf_comp_slv.value) do _; grp_active_slv[] > 0 && _update_slv_grp_plots!(); end

        # ── Export helpers ────────────────────────────────────────────
        function _export_fig(fig, ax, ylabel_str, xlabel_str, title_str, fmt)
            path = _pick_save_file(; title="Save plot (.$fmt)")
            isempty(path) && return
            endswith(path, ".$fmt") || (path = "$path.$fmt")
            ax.ylabel = ylabel_str
            ax.xlabel = xlabel_str
            ax.title  = title_str
            try
                CairoMakie.save(path, fig)
                status_obs[] = "Saved: $path"
            catch e
                status_obs[] = "Export error: $(sprint(showerror, e))"
            finally
                ax.ylabel = ""
                ax.xlabel = ""
                ax.title  = ""
            end
        end

        function _export_csv(data)
            data === nothing && (status_obs[] = "No data to export — run a plot first"; return)
            path = _pick_save_file(; title="Save data (.csv)")
            isempty(path) && return
            endswith(path, ".csv") || (path = "$path.csv")
            try
                open(path, "w") do io
                    cols = ["d"]
                    data.total_mddf !== nothing && push!(cols, "Total_MDDF")
                    for lab in data.group_labels; push!(cols, "$(lab)_mddf"); end
                    data.total_cn !== nothing && push!(cols, "Total_CN")
                    for lab in data.group_labels; push!(cols, "$(lab)_cn"); end
                    println(io, join(cols, ","))
                    for j in eachindex(data.d)
                        vals = [string(data.d[j])]
                        data.total_mddf !== nothing && push!(vals, string(data.total_mddf[j]))
                        for k in eachindex(data.group_labels); push!(vals, string(data.mddf_curves[k][j])); end
                        data.total_cn !== nothing && push!(vals, string(data.total_cn[j]))
                        for k in eachindex(data.group_labels); push!(vals, string(data.cn_curves[k][j])); end
                        println(io, join(vals, ","))
                    end
                end
                status_obs[] = "Saved: $path"
            catch e
                status_obs[] = "Export error: $(sprint(showerror, e))"
            end
        end

        on(btn_export_mddf_sol.value) do _
            _export_fig(fig_sol_mddf, ax_sol_mddf, "MDDF(r)", "r (Angstrom)", "Solute MDDF Group Contributions", String(dd_export_fmt_sol.value[]))
        end
        on(btn_export_cn_sol.value) do _
            _export_fig(fig_sol_cn, ax_sol_cn, "Coordination number", "r (Angstrom)", "Solute Coord. Number Group Contributions", String(dd_export_fmt_sol.value[]))
        end
        on(btn_export_csv_sol.value)  do _; _export_csv(last_sol_data[]); end
        on(btn_export_mddf_slv.value) do _
            _export_fig(fig_slv_mddf, ax_slv_mddf, "MDDF(r)", "r (Angstrom)", "Solvent MDDF Group Contributions", String(dd_export_fmt_slv.value[]))
        end
        on(btn_export_cn_slv.value) do _
            _export_fig(fig_slv_cn, ax_slv_cn, "Coordination number", "r (Angstrom)", "Solvent Coord. Number Group Contributions", String(dd_export_fmt_slv.value[]))
        end
        on(btn_export_csv_slv.value)  do _; _export_csv(last_slv_data[]); end

        # ── Tab 1: export ─────────────────────────────────────────────
        on(btn_export_mddf1.value) do _
            last_tab1_data[] === nothing && (status_obs[] = "No data to export — load a result first"; return)
            _export_fig(fig1_mddf, ax_mddf, "MDDF(r)", "r (Angstrom)", "MDDF", String(dd_export_fmt1.value[]))
        end
        on(btn_export_kb1.value) do _
            last_tab1_data[] === nothing && (status_obs[] = "No data to export — load a result first"; return)
            _export_fig(fig1_kb, ax_kb, "KB (L/mol)", "r (Angstrom)", "Kirkwood-Buff Integral", String(dd_export_fmt1.value[]))
        end
        on(btn_export_csv1.value) do _
            d = last_tab1_data[]
            d === nothing && (status_obs[] = "No data to export — load a result first"; return)
            path = _pick_save_file(; title="Save data (.csv)")
            isempty(path) && return
            endswith(path, ".csv") || (path = "$path.csv")
            try
                open(path, "w") do io
                    println(io, "d,MDDF,KB_L_per_mol")
                    for j in eachindex(d.d)
                        println(io, "$(d.d[j]),$(d.mddf[j]),$(d.kb[j])")
                    end
                end
                status_obs[] = "Saved: $path"
            catch e
                status_obs[] = "Export error: $(sprint(showerror, e))"
            end
        end

        # ── Tab 4 (RC): export data ───────────────────────────────────
        on(btn_export_csv_rc.value) do _
            d = last_rc_data[]
            d === nothing && (status_obs[] = "No data to export — run Update first"; return)
            path = _pick_save_file(; title="Save residue contributions (.csv)")
            isempty(path) && return
            endswith(path, ".csv") || (path = "$path.csv")
            try
                open(path, "w") do io
                    nres = length(d.residue_names)
                    header = vcat(["d"], ["mddf_$(d.residue_names[i])" for i in 1:nres],
                                        ["cn_$(d.residue_names[i])"   for i in 1:nres])
                    println(io, join(header, ","))
                    for j in eachindex(d.d)
                        vals = [string(d.d[j])]
                        for i in 1:nres; push!(vals, string(d.zmat_mddf[i, j])); end
                        for i in 1:nres; push!(vals, string(d.zmat_cn[i, j])); end
                        println(io, join(vals, ","))
                    end
                end
                status_obs[] = "Saved: $path"
            catch e
                status_obs[] = "Export error: $(sprint(showerror, e))"
            end
        end

        # ── Tab 2/3: apply group limits ───────────────────────────────
        on(btn_grp_lims_sol.value) do _
            xlims!(ax_sol_mddf, Float64(tf_sol_xmin.value[]), Float64(tf_sol_xmax.value[]))
            xlims!(ax_sol_cn,   Float64(tf_sol_xmin.value[]), Float64(tf_sol_xmax.value[]))
            ylims!(ax_sol_mddf, Float64(tf_sol_mddf_ymin.value[]), Float64(tf_sol_mddf_ymax.value[]))
            ylims!(ax_sol_cn,   Float64(tf_sol_cn_ymin.value[]),   Float64(tf_sol_cn_ymax.value[]))
        end
        on(btn_grp_lims_slv.value) do _
            xlims!(ax_slv_mddf, Float64(tf_slv_xmin.value[]), Float64(tf_slv_xmax.value[]))
            xlims!(ax_slv_cn,   Float64(tf_slv_xmin.value[]), Float64(tf_slv_xmax.value[]))
            ylims!(ax_slv_mddf, Float64(tf_slv_mddf_ymin.value[]), Float64(tf_slv_mddf_ymax.value[]))
            ylims!(ax_slv_cn,   Float64(tf_slv_cn_ymin.value[]),   Float64(tf_slv_cn_ymax.value[]))
        end

        # ── Tab 3: residue contributions ──────────────────────────────
        on(btn_rc_plot.value) do _
            R = result_obs[]
            R === nothing && (status_obs[] = "No results loaded"; return)
            at = atoms_obs[]
            at === nothing && (status_obs[] = "Load a PDB file first"; return)

            sel_str = String(tf_rc_sel.value[])
            dmin = Float64(tf_rc_ymin.value[])
            dmax = Float64(tf_rc_ymax.value[])

            status_obs[] = "Computing residue contributions…"
            try
                sel_atoms = select(at, sel_str)
                if isempty(sel_atoms)
                    status_obs[] = "Selection '$sel_str' matched no atoms"; return
                end
                rc_mddf = ResidueContributions(R, sel_atoms; dmin=dmin, dmax=dmax, type=:mddf, silent=true)
                rc_cn   = ResidueContributions(R, sel_atoms; dmin=dmin, dmax=dmax, type=:coordination_number, silent=true)

                nres = length(rc_mddf.resnums)
                x_pos = rc_mddf.xticks[1]
                y_d   = rc_mddf.d

                rc_range = 1:nres
                if nres > 2000
                    rc_step = nres ÷ 2000
                    rc_range = 1:rc_step:nres
                end
                x_plot = x_pos[rc_range]

                step = max(1, length(rc_range) ÷ 50)
                tick_idx = 1:step:length(x_plot)
                orig_idx = collect(rc_range)[collect(tick_idx)]
                xtick_pos = rc_mddf.xticks[1][orig_idx]
                xtick_lab = rc_mddf.xticks[2][orig_idx]

                # MDDF plot
                zmat_mddf = collect(hcat(rc_mddf.residue_contributions...)')[rc_range, :]
                clims_mddf, cscale_mddf = _set_clims_and_colorscale!(rc_mddf)
                cmap_mddf = cscale_mddf == :bwr ? :RdBu : :tempo
                nlevels_mddf = cscale_mddf == :tempo ? 5 : 12
                empty!(ax_rc_mddf)
                contourf!(ax_rc_mddf, x_plot, y_d, zmat_mddf; colormap=cmap_mddf, levels=nlevels_mddf)
                ax_rc_mddf.xticks = (xtick_pos, xtick_lab)
                ax_rc_mddf.xticklabelrotation = π / 3
                if length(fig3_mddf.layout.content) > 1
                    try delete!(fig3_mddf.layout.content[end].content) catch end
                end
                Colorbar(fig3_mddf[1, 2]; colormap=cmap_mddf, limits=clims_mddf,
                    label="Contribution", labelsize=10, ticklabelsize=9)

                # Coordination number plot
                zmat_cn = collect(hcat(rc_cn.residue_contributions...)')[rc_range, :]
                clims_cn, cscale_cn = _set_clims_and_colorscale!(rc_cn)
                cmap_cn = cscale_cn == :bwr ? :RdBu : :tempo
                nlevels_cn = cscale_cn == :tempo ? 5 : 12
                empty!(ax_rc_cn)
                contourf!(ax_rc_cn, x_plot, y_d, zmat_cn; colormap=cmap_cn, levels=nlevels_cn)
                ax_rc_cn.xticks = (xtick_pos, xtick_lab)
                ax_rc_cn.xticklabelrotation = π / 3
                if length(fig3_cn.layout.content) > 1
                    try delete!(fig3_cn.layout.content[end].content) catch end
                end
                Colorbar(fig3_cn[1, 2]; colormap=cmap_cn, limits=clims_cn,
                    label="Contribution", labelsize=10, ticklabelsize=9)

                last_rc_data[] = (
                    d            = copy(y_d),
                    x_pos        = copy(x_pos),
                    residue_names = rc_mddf.xticks[2],
                    zmat_mddf    = collect(hcat(rc_mddf.residue_contributions...)'),
                    zmat_cn      = collect(hcat(rc_cn.residue_contributions...)'),
                )
                status_obs[] = "Residue contributions updated ($nres residues)"
            catch e
                status_obs[] = "Error: $(sprint(showerror, e))"
            end
        end

        # ── Tab 4 (RC): apply limits ──────────────────────────────────
        on(btn_rc_lims.value) do _
            xlo = parse(Int, tf_rc_xmin.value[]); xhi = parse(Int, tf_rc_xmax.value[])
            xlims!(ax_rc_mddf, xlo, xhi); xlims!(ax_rc_cn, xlo, xhi)
            # y-limits are dmin/dmax — recompute the plot
            notify(btn_rc_plot.value)
        end

        # ── Tab 4 (RC): export figures ────────────────────────────────
        on(btn_export_mddf_rc.value) do _
            last_rc_data[] === nothing && (status_obs[] = "No data to export — run Update first"; return)
            _export_fig(fig3_mddf, ax_rc_mddf, "r (Angstrom)", "Residue", "Residue Contributions to MDDF", String(dd_export_fmt_rc.value[]))
        end
        on(btn_export_cn_rc.value) do _
            last_rc_data[] === nothing && (status_obs[] = "No data to export — run Update first"; return)
            _export_fig(fig3_cn, ax_rc_cn, "r (Angstrom)", "Residue", "Residue Contributions to Coordination Number", String(dd_export_fmt_rc.value[]))
        end

        # ── Preload if provided ────────────────────────────────────────
        if !isnothing(result) && !isnothing(pdbfile) &&
                isfile(result) && isfile(pdbfile)
            try
                R  = ComplexMixtures.load(result)
                at = read_pdb(pdbfile)
                atoms_obs[] = at
                result_obs[] = R
                tf_comp_slv.value[] = guess_solvent_selection(at, R)
                _reset_ui!(R)
                status_obs[] = "Loaded: $result"
            catch e
                status_obs[] = "Error on preload: $(sprint(showerror, e))"
            end
        end

        # ── Assemble page ─────────────────────────────────────────────
        _version = string(pkgversion(ComplexMixtures))
        _version_gui = string(pkgversion(ComplexMixturesGUI))
        return DOM.div(
            _CSS,
            DOM.div(class="cm-title", "ComplexMixtures v$(_version) / ComplexMixturesGUI v$(_version_gui)"),
            DOM.div(class="cm-main", sidebar, plots_panel),
            status_bar,
        )
    end

    server = Bonito.Server(app, "0.0.0.0", port)
    url = "http://localhost:$port"
    @info "ComplexMixtures GUI running at $url"
    try
        Bonito.open_browser(url)
    catch
        @info "Open $url in your browser"
    end
    return server
end

end # module ComplexMixturesGUI
