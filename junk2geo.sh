#!/bin/bash

usage()
{
cat << EOF
usage: $0 [OPTIONS]

Use fuzzy text match to geocode input TSV using GeoNames.
Uses all possible alternate placenames provided by Geonames and allows for the number of typos specified by the user.
Output is meant to be handed to match_metrics.sh to pare down according to various indices like Double Metaphone and Levenshtein distance.

OPTIONS:
   -h      show this message
   -e      number of errors to allow in matched text. This is according to tre-agrep.
   -g      input GeoNames SQLite database made by https://github.com/albert-decatur/geonames2sqlite
   -i      input TSV to geocode, with two columns: 1) country ISO3(s), 2) text to geocode.

Example: $0 -e 1 -g geonames/geonames_2014-10-02.sqlite -i input.tsv

EOF
}

while getopts "he:g:i:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         e)
             errors=$OPTARG
             ;;
         g)
             geonames=$OPTARG
             ;;
         i)
             to_geo=$OPTARG
             ;;
     esac
done

	#tre-agrep -E $errors -w -e "$place" --show-position $to_geo |\
