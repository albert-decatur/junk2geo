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
   -i      input TSV to geocode, with two columns: 1) country ISO2(s), 2) text to geocode. 

Multiple values of ISO2 ought to be pipe separated in the second column of the input TSV (using the -i flag) like so: IR|US|CN.
If no ISO2 is appropriate simply do not include any. 
Example use: $0 -e 1 -g geonames/geonames_2014-10-02.sqlite -i test/crs2014-06-16_sample.tsv

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
# make apostraphe a variable for GNU parallel
a="'"
cat $to_geo |\
mawk -F'\t' '{print $1}'|\
sed '1d'|\
sort|\
uniq|\
parallel -j 1 --gnu '
	iso2s=$( echo {} | tr "|" "\n" )
	# if ISO2 list is not blank (which signifies use all ISO2) then write the SQL to make a table with all of the allCountries table given those ISO2
	# this strategy presumes that queries will be used many times each
	if [[ -n $( echo "$iso2s" | grep -vE "^$" ) ]]; then 
		sql=$( 
			echo "$iso2s" |\
			sed "s:^:'$a':g;s:^:countrycode = :g;s:$:'$a':g;s:$: OR:g" |\
			tr "\n" " " |\
			sed "s:OR $::g" |\
			sed "s:^:DROP TABLE IF EXISTS \"{}\"\; CREATE TABLE \"{}\" AS SELECT geonameid,name,asciiname,alternatenames FROM allCountries WHERE :g;s:$:\;:g"
		)
	fi
	echo "$sql"|\
	sqlite3 '$geonames'
'
