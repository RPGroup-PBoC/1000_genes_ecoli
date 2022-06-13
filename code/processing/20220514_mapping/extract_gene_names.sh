#!/bin/bash
############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "Add description here."
   echo
   echo "Syntax: scriptTemplate [-g|h|v|V]"
   echo "options:"
   echo "h     Print this Help."
   echo "v     Verbose mode."
   echo "x     add other options here."
   echo
}

############################################################
############################################################
# Main program                                             #
############################################################

# Info(in_file, out_dir)
# {
#    # Display Help
#    filename="${in_file##*/}"
#    echo "Add description here."
#    echo
#    echo "Syntax: scriptTemplate [-g|h|v|V]"
#    echo "options:"
#    echo "h     Print this Help."
#    echo "v     Verbose mode."
#    echo "x     add other options here."
#    echo
# }

############################################################
############################################################
# Process the input options.                               #
############################################################
# Get the options
while getopts ":hi:o:bn:" option; do
   case $option in
      h) # display Help
         Help
         exit;;
      i) # Input file or directory
         in_file=$OPTARG;;
      o) # Output directory
         out_dir=$OPTARG;;
      b) # input file is BAM format
         Name=$OPTARG;;
      n) # Ener a name
         Name=$OPTARG;;     
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done

# Find working directiory
# result=${PWD##*/}

# parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# # Go back path
# parent_path=${parent_path%/*}
# parent_path=${parent_path%/*}
# parent_path=${parent_path%/*}

# # Find data directory
# folder=$parent_path'/data/processed_promoters/'

# # Make directories for stored data
# mkdir $parent_path'/data/processed_promoters/barcodes'

# Start the process
start=$SECONDS

# Input file name
echo
echo "Assigning gene names to promoter-barcode pairs..."

# Extract promoter-bc pairs and corresponding gene names
awk -v o="$out_dir" 'BEGIN{FS="\t";OFS = ","} !(NR%5000000){print NR " Promoters Processed"}; NF>10{gsub(/_/, ",", $1); print $10,$1,$3 >> (o"/"$3"_barcodes.txt")}' "$in_file"

# terminal output message
echo "All Promoters Processed, now adding headers..."

# Loop through output directory and add a header to each file
cd $out_dir
echo "promoter,barcode,counts,name" > headerfile
for file in *barcodes.txt; do cat headerfile $file > tmpfile2; mv tmpfile2 "$file"; done
rm headerfile

# terminal output message
echo "done! Output files written to " "$out_dir"
end=$SECONDS
duration=$(( end - start ))
echo
echo "time elapsed: $duration seconds"
# for f in 'barcodes/*.txt'; do
#    { ed "$f" < 
#    1i
#    promoter,barcode,counts,name
#    .
#    x
# }
# done


