#!/bin/bash

#TODO
# 1. add optional flag to clear non-standard tables from sqlite db - eg, ISO2 list tables
# 2. add flag for not using alt names
# 3. add flag for ignoring country names

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

function mk_iso2_tables { 
	# make apostraphe a variable for GNU parallel
	a="'"
	# print the ISO2 field from the input and get unique lists of ISO2s
	cat $to_geo |\
	mawk -F'\t' '{print $1}'|\
	sed '1d'|\
	sort|\
	uniq|\
	# for each ISO2 list, make a table with all fields from allCountries given these ISO2s - this will be removed from the db later
	# this strategy presumes that queries will be used many times each
	# note that the -j flag controls number of simultaneous jobs
	parallel -j 3 --gnu '
		iso2s=$( echo {} | tr "|" "\n" )
		# if ISO2 list is not blank (which signifies use all ISO2) then write the SQL to make a table with all of the allCountries table given those ISO2
		if [[ -n $( echo "$iso2s" | grep -vE "^$" ) ]]; then 
			sql=$( 
				echo "$iso2s" |\
				sed "s:^:'$a':g;s:^:countrycode = :g;s:$:'$a':g;s:$: OR:g" |\
				tr "\n" " " |\
				sed "s:OR $::g" |\
				sed "s:^:CREATE TABLE IF NOT EXISTS \"{}\" AS SELECT geonameid,name,asciiname,alternatenames FROM allCountries WHERE :g;s:$:\;:g"
			)
		fi
		echo "$sql"|\
		sqlite3 '$geonames'
	'
}

function rm_iso2_tables {
	# remove all but the original tables from geonames2sqlite
	# relies on tables not having whitespace in name
	# first get list of tables to keep
keep_tables=$(
cat <<EOF
admin1codesascii
admin2codes
allCountries
countryInfo
featurecodes_en
hierarchy
EOF
	)
	# get the list of all tables currently in the db
	all_tables=$( echo ".tables" | sqlite3 $geonames |tr '[:blank:]' '\n'|grep -vE "^$" )
	# get the list of tables to delete
	delete_tables=$( grep -vf <( echo "$keep_tables" )  <( echo "$all_tables" ) )
	# for each table, write and execute the SQL to delete it
	for table in $delete_tables
	do
		echo "DROP TABLE \"$table\";"|\
		sqlite3 $geonames
	done	
}

# for each unique iso2 combination, get the text to geocode and the table with geonames
# make apostraphe variable for GNU parallel
a="'"
cat $to_geo |\
mawk -F'\t' '{ print $1 }'|\
sed '1d'|\
sort|\
uniq|\
parallel --gnu '
	iso2s=$( echo {} )
	if [[ -n $iso2s ]]; then
		table={}
		doc=$( 
			# not sure why this tab cant be \t
			grep -E "^$table	" '$to_geo' |\
			mawk -F"\t" "{print \$2}" 
		)
		names=$( 
			echo -e "select name from \"$table\";" |\
		 	sqlite3 '$geonames' |\
			grep -vE "^$" 
		)
		asciinames=$( 
			echo -e "SELECT asciiname FROM \"$table\";" |\
			sqlite3 '$geonames' |\
			grep -vE "^$" 
		)
		altnames=$( 
			echo -e "SELECT CASE WHEN alternatenames IS NOT NULL THEN REPLACE(alternatenames,'$a','$a','$a'\n'$a') END AS alternatenames FROM \"$table\";"  |\
			sqlite3 '$geonames' |\
			grep -vE "^$" 
		)
		allnames=$( echo -e "$names\n$asciinames\n$altnames" )
		# measure number of terms in the bag of words of the doc to geocode (all records to geocode with that iso2 list) and the geonames for that iso2 list
		doc_bow=$(
			echo "$doc" |\
			# normalize whitespace	
			sed "s:[ \t]\+: :g" |\
			# spaces to newline
			tr " " "\n"|\
			# punctiation to newline
			tr "[:punct:]" "\n" |\
			# all characters to lowercase
			mawk "{ print tolower(\$0) }" |\
			sort |\
			uniq |\
			grep -vE "^$" |\
			mawk "{ if( length(\$0) > 3 ) print \$0 }"
		)
		count_terms_doc_bow=$(
			echo "$doc_bow" |\
			wc -l 
		)
		count_terms_geonames=$(
			echo "$allnames" |\
			wc -l
		)
		if [[ $count_terms_doc_bow > $count_terms_geonames ]]; then
			echo -e "$count_terms_doc_bow\t$count_terms_geonames"
		fi
		#echo -e {}"\t$doc"
	else
		# there are no iso2s
		false
	fi
'

#mk_iso2_tables
#rm_iso2_tables
