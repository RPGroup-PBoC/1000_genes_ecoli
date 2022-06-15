#!/bin/bash
group=${1:-110}
# Find working directiory
result=${PWD##*/}

PARENT_PATH=$(dirname $(readlink -f $0))

# Go back path
parent_path=${parent_path%/*}
parent_path=${parent_path%/*}
parent_path=${parent_path%/*}



# Make directories if not existent
mkdir $parent_path'/data/barcodes/'$result'/'$group'_per_gene_filtered/'
mkdir $parent_path'/data/barcodes/'$result'/'$group'_per_gene/'

out_folder=$parent_path'/data/barcodes/'$result'/'$group'_per_gene_filtered/'
data_folder=$parent_path'/data/barcodes/'$result'/'$group'_per_gene/*'

for FILE in $data_folder;do
  GENE="${FILE##*/}"
  GENE="${GENE%.*}"
  awk -F"," '$3>2 {print $0}' $FILE > $out_folder$GENE'_filtered.txt'
done