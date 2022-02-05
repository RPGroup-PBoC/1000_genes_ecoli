using BioSequences, DataFrames, CairoMakie

import ..enzyme_list
using ..wgregseq: design.import_primer



function check_dataframe(df; print_results=true, site_start=1, site_end=nothing)
    gdf = groupby(df, :promoter)
    max_list, min_list = Float64[], Float64[]
    for _df in gdf
        promoter = _df.promoter |> unique
        if print_results
            println("Promoter: $promoter")
            println("-------------------------")
        end
        mut_rate = mutation_coverage(_df, site_start, site_end)
        min_rate, max_rate = minimum(mut_rate), maximum(mut_rate)
        if print_results
            println("Minimum mutation rate: $(min_rate)")
            println("Maximum mutation rate: $(max_rate)")
            println()
            push!(min_list, min_rate)
            push!(max_list, max_rate)
        end
        if check_cut_sites(_df)
            if print_results
                println("Cut sites are correct.")
                println()
            end
        else
            if print_results
                println("Cut sites NOT are correct.")
                println()
            end

        end

        if check_primers(_df)
            if print_results
                println("Primers are correct.")
                println()
            end
        else
            if print_results
                println("Primes NOT are correct.")
                println()
            end

        end

        if print_results
            println()
            println()
        end
    end
    promoter = df.promoter |> unique
    fig = Figure(resolution=(15*length(promoter), 800))
    ax = Axis(fig[1, 1])
    
    scatter!(ax, 1:length(promoter), max_list, label="Maximum")
    scatter!(ax, 1:length(promoter), min_list, label="Minimum")
    lines!(ax, [1, length(promoter)], [0.1, 0.1], color="grey", linestyle=:dash)
    ax.ylabel = "Mutation Rate"
    ax.xticklabelrotation = pi/4
    ax.xticks = 1:length(promoter)
    ax.xtickformat = x -> string.(promoter)
    axislegend()
    save("plot.pdf", fig)
    return fig
end





function mutation_coverage(df, site_start=1, site_end=nothing)
    
    if isnothing(site_end)
        site_end = length(df.sequence[1])
    end 

    seq_list = [seq[site_start:site_end] for seq in df.sequence]
    mat = PFM(seq_list)
    mat = mat ./ length(seq_list)
    mut_rate = 1 .- [maximum(A) for A in eachcol(mat)]
    return mut_rate
end


function check_cut_sites(df)
    gdf = groupby(df, ["upstream_re_site", "downstream_re_site"])
    sites_correct = true
    for _df in gdf
        enz1 = unique(_df.upstream_re_site)[1]
        enz2 = unique(_df.downstream_re_site)[1]

        site1 = enzyme_list[enzyme_list.enzyme .== enz1, "site"][1]
        site2 = enzyme_list[enzyme_list.enzyme .== enz2, "site"][1]
        sites_correct *= ~any(map(seq -> seq[21:26] != LongDNASeq(site1),  _df.sequence))
        sites_correct *= ~any(map(seq -> seq[187:192] != LongDNASeq(site2),  _df.sequence))
    end
    return sites_correct
end


function check_primers(df)
    primer_cols = filter(x -> occursin("primer", x), names(df))
    gdf = groupby(df, primer_cols)
    primers_correct = true
    for _df in gdf
        for col in primer_cols
            direction = split(col, "_")[1] |> string
            ind, positions  = unique(_df[!, col])[1]

            primer_seq = import_primer(ind, direction)[1:(positions[2]-positions[1]+1)]
            primers_correct *= ~any(map(seq -> seq[positions[1]:positions[2]] != LongDNASeq(primer_seq),  _df.sequence))
        end
    end
    return primers_correct
end