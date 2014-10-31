#!/bin/bash

#TODO
# add flag for ignoring country names for geocoding (from countryInfo table)
# add flag for GNU parallel so can be run on multi host.  will have to transfer SQLite DB, input TSV - have not had success with -trc flag
# note when the same text is used to match to more than one placename
# user control over how much smaller a doc bow must be before it's used to search for geonames subset?
# user control over max geonames returns per ASCII doc term?
# is passing doc terms to ASCII//TRANSLIT for the benefit of agrep while selecting geo_candidates causing a problem with alternate place names not being selected?
# how to handle backticks (`) and other shell interpretted or regex characters in placenames?
# clean up tmp files

usage()
{
cat << EOF
usage: $0 -e n [-d] [-a] [-s|-S stopwords/stopwords_en_es_fr_pt_de_it.txt] [-l n] -g geonames/geonames_2014-10-02.sqlite -i test/crs2014-06-16_sample.tsv

Use fuzzy text match and GeoNames to geocode input TSV.
Allows for the number of typos specified by the user and can use or not use GeoNames alternate names (typically these are non-English).
Output is meant to be handed to match_metrics.sh to pare down according to various indices like Double Metaphone and Levenshtein distance.

OPTIONS:
   -h      show this message
   -e      number of errors to allow in matched text
   -g      input GeoNames SQLite database made by https://github.com/albert-decatur/geonames2sqlite
   -i      input TSV to geocode, with two columns: 1) country ISO2(s), 2) text to geocode
   -d      drop the ISO2 subset tables based on GeoNames' allCountries. Warning: these can take several minutes to recreate
   -a      use GeoNames alternate names as well as "name" and "asciiname".  Altnerate names are in as many languages as possible
   -s      do not allow any terms from this list of stopwords to be considered a match.  One line per stopword. Consider this a blacklist.
   -S      same as -s but intended for a very large list of stopwords.  This flag will make a temporary stopword list composed only of terms that appear at least once in the input TSV. If a /tmp/stopwords exists it will be used. Cannot be used with -s.
   -l      match must be at least this length to be considered a candidate.  Very short matches are typically junk, but you may miss out on very short placenames

Multiple values of ISO2 ought to be pipe separated in the first column of the input TSV (using the -i flag) like so: IR|US|CN.
If no ISO2 is appropriate simply do not include any.  However, terms for all of GeoNames will be searched so try to include some ISO2s where you can. A whole continent worth of ISO2s is much better than trying to geocode from the whole earth.
The '-S' flag will make a temporary stopword list at /tmp/stopwords.  This is in case you want to preserve this list.
Example use: $0 -e 1 -g geonames/geonames_2014-10-02.sqlite -i test/crs2014-06-16_sample.tsv

EOF
}

while getopts "hdae:g:i:s:S:l:" OPTION
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
         d)
             drop_iso2_tables=1
             ;;
         a)
             use_alts=1
             ;;
         s)
             use_stopwords=1
             stopwords=$OPTARG
             ;;
         S)
             use_big_stopwords=1
             big_stopwords=$OPTARG
             ;;
         l)
             use_length=1
             length=$OPTARG
             ;;
     esac
done

# allow GNU parallel to use stopwords user arg
if [[ $use_stopwords -ne 1 ]]; then
	use_stopwords=0
elif [[ $use_stopwords -eq 1 ]] && [[ $use_big_stopwords -eq 1 ]]; then
	echo -e "\nYou cannot use both the regular stopwords flag '-s' *and* the big stopwords flag '-S' at the same time.\nPlease choose one!\n"
	exit 1
fi
# allow GNU parallel to use length user arg
if [[ $use_length -ne 1 ]]; then
	use_length=0
fi
# allow GNU parallel to use use_alts
if [[ $use_alts -ne 1 ]]; then
	use_alts=0
fi


function mk_iso2_tables { 
	# print the ISO2 field from the input and get unique lists of ISO2s
	cat $to_geo |\
	mawk -F'\t' '{print $1}'|\
	sed '1d'|\
	sort|\
	uniq|\
	# for each ISO2 list, make a table with all fields from allCountries given these ISO2s - this will be removed from the db later
	# this strategy presumes that queries will be used many times each
	# note that the -j flag controls number of simultaneous jobs, and SQLite's lock prevents use from doing more than one job at once on a given host
	# one work around would actually be to write these tables to new SQLite dbs, probably under a $(mktemp -d)
	parallel -j 1 --gnu '
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
	## vacuum to take up less space - this could take a while!
	#echo "vacuum;" |\
	#sqlite3 $geonames
}

function big_stopwords {
	# if /tmp/stopwords exists it will be used.  remove this file if it is irrelevant!
	stopwords=/tmp/stopwords
	if [[ -f $stopwords ]]; then
		# use existing /tmp/stopwords
		false
	else
		# match input TSV text word by word to big stopwords list
		LANG=C grep -owiFf $big_stopwords <( cat $to_geo | mawk -F"\t" "{print \$2}" ) |\
		mawk "{print tolower(\$0)}" |\
		sort |\
		uniq > /tmp/stopwords
	fi
}

function get_geonames { 
	# apostraphe variable for GNU parallel
	a="'"
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
			# get all text from input TSV that relates to this list of ISO2s
			doc=$( 
				# not sure why this tab cant be \t
				grep -E "^$table	" '$to_geo' |\
				mawk -F"\t" "{print \$2}" 
			)
			# get geonames names field
			names=$( 
				echo -e "select name from \"$table\";" |\
				sqlite3 '$geonames' |\
				grep -vE "^$" 
			)
			# get geonames asciinames field
			asciinames=$( 
				echo -e "SELECT asciiname FROM \"$table\";" |\
				sqlite3 '$geonames' |\
				grep -vE "^$" 
			)
			# use altnames or dont according to user -a flag
			# note that we define local var using var from outside GNU parallel
			use_alts='$use_alts'
			if [[ -n $use_alts ]]; then
				altnames=$( 
					echo -e "SELECT CASE WHEN alternatenames IS NOT NULL THEN REPLACE(alternatenames,'$a','$a','$a'\n'$a') END AS alternatenames FROM \"$table\";"  |\
					sqlite3 '$geonames' |\
					grep -vE "^$" 
				)
				allnames=$( echo -e "$names\n$asciinames\n$altnames" )
			else
				allnames=$( echo -e "$names\n$asciinames" )
			fi
			# names are often the same - eg "name" and "asciiname" entries
			# remove double quotes - these will be used to encase multiterm place names
			# TODO will have to deal with missing double quotes when matching back to geoname id, unless double quotes are never used
			allnames=$(
				echo "$allnames" |\
				sort |\
				uniq |\
				sed "s:\"::g"
			)
			# if use length, allname must be greater than specified length
			if [[ '$use_length' -eq 1 ]]; then
				allnames=$( mawk "{ if( length(\$0) > '$length' ) print \$0 }" <( echo "$allnames" ) )
				# DELETE
				echo "$allnames" > /tmp/allnames
			fi	
			# if use stopwords, allnames cannot be stopword
			if [[ '$use_stopwords' -eq 1 ]]; then
				allnames=$(
					grep -vFxf '$stopwords' <(echo "$allnames" )	
				)
			fi
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
				mawk "{ if( length(\$0) > 3 ) print \$0 }" |\
				# cant have a number
				grep -vE "[0-9]" |\
				# make ascii
				# this slows things down a ton but agrep fails sometimes without it, even with -k flag
				# one possibility is to use tre-agrep later to find geonames candidates without using iconv here
				iconv -c -f utf8 -t ASCII//TRANSLIT
			)
			# if use length, doc bag of words terms must be greather than specified length - but only after removing punctuation and whitespace
			if [[ '$use_length' -eq 1 ]]; then
				docbowtmp=$(mktemp)
				echo "$doc_bow" > $docbowtmp
				passes_length=$( 
					echo "$doc_bow" |\
					tr -d "[:punct:]" |\
					sed "s:[ \t]\+::g" |\
					# note use of FNR to get current 1-indexed record number
					mawk "{ if( length(\$0) > '$length' ) print FNR}" 
				)
				# build a sed statement to pass to bash that will print those records mentioned by awk FNR - these records met the length requirement
				doc_bow=$( 
					echo "$passes_length" |\
					sed "s:^:sed -n \":g;s:$:p\" $docbowtmp:g" |\
					bash
				)
			fi	
			# if use stopwords, doc bag of words cannot have stopwords
			if [[ '$use_stopwords' -eq 1 ]]; then
				doc_bow=$(
					grep -vFxf '$stopwords' <(echo "$doc_bow" )	
				)
			fi
			# DELETE
			echo "$doc_bow" > /tmp/doc_bow
			count_terms_doc_bow=$(
				echo "$doc_bow" |\
				wc -l 
			)
			count_terms_geonames=$(
				echo "$allnames" |\
				wc -l
			)
			# if the doc bag of words has *far* fewer terms than geonames then use each term in the bow to make an intermediate list of geonames to search the doc with
			# ultimately this should be based on the average number of geonames candidates that are selected for each doc term. right now its a guess.
			# consider using agreps -f patternfile here.  problem: limit of 30k terms.  also terms with match far far too many cannot be ignored
			weight=350
			if [[ $( expr "$count_terms_doc_bow" \* $weight ) -lt "$count_terms_geonames" ]]; then
				geo_candidates=$(
					for doc_term in $doc_bow
					do
						geonames_from_doc_bow=$( agrep -'$errors' -i -w -k "$doc_term" <( echo "$allnames" ) )
						c=$( echo "$geonames_from_doc_bow" | wc -l )
						# if the term matches far too many possible geonames then simply ignore it
						# should maybe make the max/min here user args
						if [[ $c -lt 1000 ]] && [[ $c -gt 0 ]]; then
							echo "$geonames_from_doc_bow" | grep -vE "^$"
						fi
					done
				)
			else
				# doc has more terms than geonames for the iso2s selected
				geo_candidates="$allnames"
			fi
		else
			# there are no iso2s - use allCounties table from SQLite in its entirety
			# TODO: must move end of if statement so that stopwords, length, etc apply when there are no iso2s
			geo_candidates="$allnames"
		fi
		# send doc text to file
		tmpdoc=$(mktemp)
		echo "$doc" > $tmpdoc
		# for each geonames candidate, tre-agrep for the text that was matched
		# could we use a patternfiles here instead of a loop? pattern file length could be limiting but could split
		while read geo_candidate
		do
			# get geonames candidates that match according to number of user errors
			matchtmp=$(mktemp)
			# this is where the fuzzy text match happens to find place names
			tre-agrep -E '$errors' -w -e "$geo_candidate" --show-position $tmpdoc |\
			while read matchline
			do
				characterRange=$(
					echo "$matchline" |\
					grep -oE "^*[^:]+" |\
					awk -F"-" "{OFS=\"-\"}{print \$1+1,\$2+1}"
				)
				match=$(
					echo "$matchline" |\
					sed "s:^[0-9]\+-[0-9]\+\:::g" |\
					cut -c $characterRange
				)
				# if use length, match must be greather than specified length - but only after removing punctuation and whitespace
				if [[ '$use_length' -eq 1 ]]; then
					passes_length=$( 
						echo "$match" |\
						tr -d "[:punct:]" |\
						sed "s:[ \t]\+::g" |\
						mawk "{ if( length(\$0) > '$length' ) print 1 }" 
					)
					# if it does not pass the length test then there is no match
					if [[ "$passes_length" -ne 1 ]]; then
						match=
					fi
				fi
				# if use stopwords, match cannot be stopword
				if [[ '$use_stopwords' -eq 1 ]]; then
					match=$(
						# remove whitespace, punctuation, and make lowercase when comparing to sotpwords
						grep -vFxf '$stopwords' <( echo "$match" | tr -d "[:punct:]" | sed "s:[ \t]\+::g" | mawk "{ print tolower(\$0) }" )
					)
				fi	
				# if there is a match then print it, the geo_candidate it matched, and the body text record the match text came from
				if [[ -n "$match" ]]; then
					body=$(
						echo "$matchline" |\
						# remove tre-agrep match character range
						sed "s/^[0-9]\+-[0-9]\+://g"
					)
					echo -e "$geo_candidate\t$match\t$body"
				fi
			done > $matchtmp
#			# must find geonameids for each geo_candidate
#			# pipe separate if multiple
#			# first make a list of unique geo_candidates that had a match
#			uniq_geo_candidates_w_match=$(
#				cat $matchtmp |\
#				mawk -F"\t" "{ print \$1 }" |\
#				sort |\
#				uniq
#			)
#			# make a variable with the iso2s table as TSV that has geonameid and all name variants allowed (use_alts or not according to user args)
#			if [[ '$use_alts' -eq 1 ]]; then
#				table_w_geonameids=$( 
#					echo -e ".mode tabs\nSELECT geonameid,name,asciiname,CASE WHEN alternatenames IS NOT NULL THEN REPLACE(alternatenames,'$a','$a','$a'\t'$a') END AS alternatenames FROM \"$table\";" |\
#					sqlite3 '$geonames'
#				)
#			else
#				table_w_geonameids=$( 
#					echo -e ".mode tabs\nSELECT geonameid,name,asciiname FROM \"$table\";" |\
#					sqlite3 '$geonames'
#				)
#			fi
#			# for each geo_candidate that had a match, find corresponding geonameids
#			# then join this back to matchtmp according to geo_candidate names
#			geonameidstmp=$(mktemp)
#			echo "$uniq_geo_candidates_w_match" |\
#			while read needs_geonameids 
#			do
#				geonameids=$(
#					# not sure why these tabs cant be \t
#					LANG=C grep -E "	$needs_geonameids	" <( echo "$table_w_geonameids" ) |\
#					mawk -F"\t" "{print \$1}" |\
#					tr "\n" "|" |\
#					sed "s:|$::g"
#				)
#				echo -e "$geonameids\t$geo_candidate"
#			done > $geonameidstmp
		# DELETE
		echo -e "matchtmp is $matchtmp\ngeonameidstmp is $geonameidstmp"
		done < <( echo "$geo_candidates" )
	'
}

# invoke functions
if [[ $use_big_stopwords -eq 1 ]]; then
	big_stopwords
fi
if [[ $drop_iso2_tables -eq 1 ]]; then
	rm_iso2_tables
else
	mk_iso2_tables
fi
get_geonames
