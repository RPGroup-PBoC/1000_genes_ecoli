using wgregseq, FASTX, DataFrames, CSV, BioSequences, CairoMakie,  StatsBase, Dates

# Set path
dir = @__DIR__
home_dir = joinpath(split(dir, "/")[1:end-3])

# Import genome
re = open(FASTA.Reader, "/$home_dir/data/ecocyc/mg1655_genome.fasta")
wt_sequence = [sequence(record) for record in re][1]

# Import original twist order from niko
df = CSV.read("/$home_dir/data/twist_orders/TWIST_sequences_niko_30000_new.csv", DataFrame)

# Extract promoter names
insertcols!(df, 1, :promoter_name => map(x -> split(x, '_')[1], df.name))

# Take negative controls and remove primers
df_negs = df[df.promoter_name .== "neg", :]
insertcols!(df_negs, 1, :promoter_seq => map(x -> x[21:180], df_negs.sequence))

# Find promoter names
df = df[df.promoter_name .!= "neg", :]
promoter_names = df.promoter_name |> unique
println(promoter_names)
# Import promoter list and infer types that can be infered automatically
promoter_list = CSV.read(
    "/$home_dir/data/promoter_list_processed.csv", 
    DataFrames.DataFrame, 
    types=Dict(
        "promoter"=>String,
        "tss"=>Float64,
        "direction"=>String
    )
)

operons_without_promoters = CSV.read(
    "/$home_dir/data/operons_without_promoters.csv", 
    DataFrames.DataFrame, 
    types=Dict(
        "direction"=>String
    )
)

# Replace columns by nicer types
promoter_list.genes = parse.(Vector{String}, promoter_list.genes)
promoter_list.gene_position = parse.(Vector{Float64}, promoter_list.gene_position)
promoter_list.evidence = parse.(Vector{String}, promoter_list.evidence)

operons_without_promoters.genes = parse.(Vector{String}, operons_without_promoters.genes)
operons_without_promoters.gene_position = parse.(Vector{Float64}, operons_without_promoters.gene_position)

## Some genes may have the wrong synomym
all_gene_list = CSV.read(
    "/$home_dir/data/all_genes_table.csv", 
    DataFrame, 
    types=Dict(
        "ID"=>String,
        "gene"=>String,
        "gene_position"=>Float64,
        "direction"=>String
    )
)


println("Finding Promoters...")
df_list = DataFrame[]
genes_no_tss = []
for prom in promoter_names
    println(prom)
    _df = promoter_list[map(x -> prom[1:4] in x, promoter_list.genes), [:tss, :direction, :gene_position, :genes, :promoter, :evidence]]
    if nrow(_df) > 0
        push!(df_list, _df)
    else
        push!(genes_no_tss, prom[1:4])
    end
end
df = vcat(df_list...) |> unique
println("Done!")
println()
## Missing TSS
println("Looking for TSS in Urtecho data set...")
# Group genes into operons / transcription units
df_no_prom = DataFrame()
for gene in genes_no_tss
    append!(df_no_prom, operons_without_promoters[map(x -> gene in x, operons_without_promoters.genes), :])
end
if nrow(df_no_prom) > 0
    unique!(df_no_prom)
end

# Look for these units in Urtecho et al. 2020 dataset
# import Urtecho data
urtecho_tss = CSV.read(
    "/$home_dir/data/urtecho_2020/tss_operon_regulation.txt", 
    DataFrame 
)


function occursin_operon(gene, operon)
    split_operon = split(operon, "-")
    a, b = gene[1:3], gene[4]
    return prod(occursin.(a, split_operon) .* occursin.(b, split_operon))
end

# Find operon in Urtecho data
df_tss_urtecho = DataFrame()

# Make array to store indeces of genes to be removed from list
delete_index_list = Int64[]
for i in 1:nrow(df_no_prom)
    genes = df_no_prom[i, "genes"]
    gene_position = df_no_prom[i, "gene_position"]
    for gene in genes
        operons = filter(x -> prod(occursin_operon.(gene, x)), urtecho_tss.operon)
        if (operons |> unique |> length) > 1
            throw(ErrorException("More than one operon for genes: $(genes)"))
        elseif  (operons |> unique |> length) == 0
            #println("No operons for genes $(genes) in Urtecho dataset.")
            #println()
        else
            operon = unique(operons)[1]
            temp = urtecho_tss[(urtecho_tss.operon .== operon) .& ((urtecho_tss.active .== "active")), :]
            if nrow(temp) != 0
                insertcols!(temp, 2, :genes => fill(genes, nrow(temp)))
                insertcols!(temp, 2, :gene_position => fill(gene_position, nrow(temp)))
                insertcols!(temp, 2, :evidence => fill(["EXP"], nrow(temp)))
                rename!(temp, "tss_strand" => "direction", "tss_position"=> "tss", "tss_name"=>"promoter")
                append!(df_tss_urtecho, temp)
                push!(delete_index_list, i)
            end
        end
    end
end

# Add found promoters to list
if nrow(df_tss_urtecho) > 0
    append!(df, df_tss_urtecho[:, ["genes", "tss", "direction", "gene_position", "promoter", "evidence"]])
end

# Remove genes with identified promoters from list of genes without promoters
df_no_prom = df_no_prom[Not(delete_index_list), :]
println("Done!")
println()

## Now we tackle the genes for which we have not found a TSS yet
# We look for the site with the strongest predicted promoter within
# 500 bases upstream of the start of the coding region
println("Predicting TSS using La Fleur model...")
p = wgregseq.promoter_finder.Promoter_Calculator()
tss_list = Int64[]
name_list = String[]

for i in 1:nrow(df_no_prom)
    if df_no_prom[i, "direction"] == "+"
        ind = Int64(minimum(df_no_prom[i, "gene_position"]))
        sequence = wt_sequence[ind-500:ind]
        r = p(sequence)["Forward_Predictions_per_TSS"]
        _x = [(key, r[key]["dG_total"]) for key in keys(r) |> collect]
        tss = _x[argmin([x[2] for x in _x])][1] + ind - 500
    else
        ind = Int64(maximum(df_no_prom[i, "gene_position"]))
        sequence = wt_sequence[ind:ind+500]
        r = p(sequence)["Reverse_Predictions_per_TSS"] 
        _x = [(key, r[key]["dG_total"]) for key in keys(r) |> collect]
        tss = _x[argmin([x[2] for x in _x])][1] + ind
    end
    push!(tss_list, tss)

    push!(name_list, join(df_no_prom[i, "genes"], "_") * "_predicted")
end

if nrow(df_no_prom) > 0 
    # Add start sites to genes 
    insertcols!(df_no_prom, 2, :tss =>tss_list)
    # Add information that they are predicted
    insertcols!(df_no_prom, 5, :promoter =>name_list)
    insertcols!(df_no_prom, 5, :evidence =>fill(["COMP"], nrow(df_no_prom)))
    # Add promoters to list
    append!(df, df_no_prom)
end

println("Done!")
println()

## For genes with multiple promoters, take the strongest predicted one
println(df)


# Create temporary DataFrame
temp_df = DataFrame()

# Go through each gene
println("Finding best promoter for genes with multiple promoters...")
for gene_list in df.genes |> unique
    # Find promoters for gene
    sub_df = df[map(x -> x == gene_list, df.genes), :]
    println(sub_df)
    # If more than one promoter, find strongest
    if nrow(sub_df) > 1
        inds = map(x -> "EXP" in x, sub_df.evidence)
        if sum(inds) == 0
            append!(temp_df, DataFrame(wgregseq.design.find_best_promoter(sub_df, wt_sequence)))
        elseif sum(inds) == 1
            append!(temp_df, sub_df[inds, :])
        else
            _df = sub_df[inds, :]
            dist_mat = _df.tss' .- _df.tss
            println(dist_mat)
            break
        end
    else
        append!(temp_df, sub_df)
    end
end

#df = temp_df

println("Done!")
println()

## Design Sequences for genes with TSS
println("Creating mutated sequences...")
df_sequences = DataFrame()
for row in eachrow(df)
    tss = Int64(row.tss)
    direction = row.direction
    genes = row.genes
    promoter = row.promoter
    seq = wgregseq.design.find_seq(tss, direction, 115, 45, wt_sequence)[1]
    mut_list = wgregseq.design.mutations_rand(seq, 0.1, 1500)
    names = ["$(promoter)_$i" for i in 0:1500]
    _df = DataFrame(sequence=mut_list, genes=fill(genes, 1501), promoter=fill(promoter, 1501), name=names)
    global df_sequences = vcat(df_sequences, _df)
end

if any(length.(df_sequences.sequence) .!= 160)
    throw(ErrorException("Not all sequences are 160bp!"))
else
    println("Done!")
    println()
end
df_sequences
## Check sequences for restriction sites 
gdf = groupby(deepcopy(df_sequences), :genes)
df_stack = DataFrame()


enzymes = ["SalI", "SacI", "NheI", "XbaI", "SpeI", "XhoI", "EcoRI", "ApaI", "ScaI", "NcoI", "MluI", "EcoRV", "BbsI", "BamHI", "AgeI", "PstI", "NsiI", "SbfI"]
println("Adding restriction enzymes...")
for enz in enzymes
    if enz ∉ wgregseq.enzyme_list.enzyme
        throw(ErrorException("$enz is not in list of enzymes."))
    end
end
println("Primer Index to use (default 100):")
primer = parse(Int64, readline())
if primer == ""
    primer = 100
end

for group in gdf
    group[:, "sequence"] = wgregseq.design.add_primer(convert(Vector{LongSequence{DNAAlphabet{4}}}, (group.sequence)), primer, "both")
    df_restriction = wgregseq.design.find_restriction_sites(enzymes, group[:, "sequence"])
    sort!(df_restriction, "sites")
    dict = Dict{Any, Any}(df_restriction.enzyme .=> df_restriction.sites)
    dict["gene"] = [unique(group.genes)[1]]
    dict["promoter"] = [unique(group.promoter)[1]]
    append!(df_stack, DataFrame(dict))
end
df_stack

dict_enz = Dict{Any, Any}(enzymes .=> sum.(eachcol(df_stack[!, enzymes])))
dict_enz["gene"] = [String31["all"]]
dict_enz["promoter"] = "all"
append!(df_stack, DataFrame(dict_enz))
println("")
println(df_stack)

# Set these enzymes to disable query
enz1 = ""
enz2 = ""

println("Upstream restriction enzyme (default is SpeI by hitting `enter`):")
while enz1 ∉ wgregseq.enzyme_list.enzyme
    global enz1 = readline()
    if enz1 == ""
        global enz1 = "SpeI"
    end
    if enz1 ∉ wgregseq.enzyme_list.enzyme
        println("$enz1 not in list of enzymes")
    end
end
println()
println("Downstream restriction enzyme (default is ApaI by hitting `enter`):")
while enz2 ∉ wgregseq.enzyme_list.enzyme
    global enz2 = readline()
    if enz2 == ""
        global enz2 = "ApaI"
    end
    if enz2 ∉ wgregseq.enzyme_list.enzyme
        println("$enz2 not in list of enzymes")
    end
end
println()

## Add restriction sites
df_sequences.sequence = wgregseq.design.add_re_sites.(df_sequences.sequence, enz1, enz2)
if any(length.(df_sequences.sequence) .!= 172)
    println(length.(df_sequences.sequence) |> unique)
    throw(ErrorException("Not all sequences are 172 after adding primers bp!"))
end

insertcols!(df_sequences, 4, :upstream_re_site => fill(enz1, nrow(df_sequences)))
insertcols!(df_sequences, 5, :downstream_re_site => fill(enz2, nrow(df_sequences)))

println("Done!")
println()

## Adding primers
# First we check that the primer does not contain the restriction site. If that happens
# we try to take the next primer

## Add reverse primers

# Go through groups of n_per_group genes and add primer

primer_0 = deepcopy(primer)

println("Adding forward and reverse primers...")


insertcols!(df_sequences, 4, :fwd_primer => fill((primer_0, (1, 20)), nrow(df_sequences)))
insertcols!(df_sequences, 5, :rev_primer1 => fill((primer_0, (231, 250)), nrow(df_sequences)))
df_sequences.sequence = wgregseq.design.add_primer(df_sequences.sequence, primer_0)

# Confirm that the primers are correct
fwd_primer = wgregseq.design.import_primer(primer_0, "fwd")
rev_primer = wgregseq.design.import_primer(primer_0, "rev")
if any([seq[1:20] != fwd_primer for seq in df_final.sequence])
    throw(ErrorException("Not all sequences have the right forward primer!"))
elseif any([seq[end-19:end] != rev_primer for seq in df_final.sequence])
    throw(ErrorException("Not all sequences have the right reverse primer!"))
else
    println("Done!")
    println()
end

##
# Save results
filename = string(Dates.today()) * "_efflux_pump_sequences.csv"
CSV.write("/$home_dir/data/twist_orders/$filename", df_sequences)
println("Sequence list saved in `/$home_dir/data/twist_orders/$filename`")
println("Total number of sequences: $(nrow(df_sequences))")