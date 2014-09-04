#!/bin/bash

# TODO: allow user to choose whether to use alternate placenames
# write another script to split geonames according to ISO2(s) supplied by user's input column, and users input according to ISO2(s).
# delete iso2 col in split outputs so that only geocoding text is used.  also hanle taking unique values.

usage()
{
cat << EOF
usage: $0 [OPTIONS]

Use fuzzy text match to provide potential geocodes for input TSV.
Uses all possible alternate placenames provided by Geonames and allows for the number of typos specified by the user.
Output is meant to be handed to fuzzyMatch_qa.sh to pare down according to various indices like Double Metaphone and Levenshtein distance.

OPTIONS:
   -h      show this message
   -e      number of errors to allow in matched text. This is according to tre-agrep. This can be pared down later by fuzzyMatch_qa.sh.
   -g      input Geonames using the format for allCountries.txt (uses all the same columns and tab separation)
   -i      input TSV to geocode, with two columns: 1) country ISO2(s), 2) text to geocode.

Example: $0 -e 1 -g geonames_EG.txt -i aiddata_EG.tsv

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

echo "geonameid|latitude|longitude|placename|match_text|aiddata_id|title|short_description|long_description"
while read geoline
do 
	altString=$(echo "$geoline" | sed 's:|: :g' | awk -F'\t' '{OFS="|"}{if($4 != "")print $1,$5,$6,$4}')
	if [[ -n "$altString" ]]; then 
		altLatLong=$(echo "$altString" | awk -F"|" '{OFS="|"}{print$2,$3}')
		geonameid=$(echo "$altString" | awk -F"|" '{print $1}')
		echo "$altString" | awk -F"|" '{print $4}' | sed 's:,:\n:g'| sed "s:^:${altLatLong}|:g;s:^:${geonameid}|:g"
		else 
			echo "$geoline" | sed 's:|: :g' | awk -F'\t' '{OFS="|"}{print $1,$5,$6,$2}'
	fi
done < $geonames |\

while read altPlaceNames
do 
	place=$(echo "$altPlaceNames" | awk -F"|" '{print $4}')
	tre-agrep -E $errors -w -e "$place" --show-position $to_geo |\
	while read matchline
	do 
		characterRange=$(echo "$matchline" | grep -oE "^*[^:]+" | awk -F"-" "{OFS=\"-\"}{print \$1+1,\$2+1}")
		match=$(echo "$matchline" | sed "s:^[0-9]\+-[0-9]\+\:::g" | cut -c $characterRange)
		body=$(echo "$matchline" | sed 's/^[0-9]\+-[0-9]\+://g')
		echo "$altPlaceNames|$(echo "$match" | sed 's:|::g')|$body"
	done
done
