#!/bin/bash

# given a pipe separated list of match_text and placename, 
# make a series of fields that record the following information relevant to reducing comission error:
#	1. is perfect match ( A == B ). 1 for TRUE and 0 for FALSE.
#	2. is perfect match without whitespace and punctuation and all lower case. 1 for TRUE and 0 for FALSE.
#	3. is perfect match if same as #2 but also converted to ASCII//TRANSLIT and only [A-Za-z] are kept. 1 for TRUE and 0 for FALSE.
#	4. string length of match_text without punctuation (very short strings are often junk). Length of string.
#	5. match text is a stopword according to user supplied file (ought to be multi-lingual) (case insensitive). 1 for TRUE and 0 for FALSE.
#	6. Levenshtein distance (higher is greater difference). Reports Levenshtein distance.
#	7. count of Double Metaphone codes that are the same between match_text and placename. Max is 2, min is 0.
#
# TODO
# user provides names of fields, path to levenshtein and double metaphone scripts, field delimiter, localhost assumed if no list of hosts given
# allow to run on multiple hosts.  may have to use -trc w/ parallel
# NB: makes sense to just use unique match_text / placename combinations with this script and match back later even if user doesn't provide these

usage()
{
cat << EOF
usage: $0 -i input.tsv -s stopwords.txt -d /path/to/doubleMetaphone -l /path/to/levensteinDistance [-b user@example_host.org,user@example_host2.org]

Record a series of string metrics for junk2geo matches.
These can later be filtered to find a combination of metrics that yield highest accuracy.
This is somehwat qualitative, but can be backed up by accuracy assessment of filtered outputs.
For example, match_text and placenames must sound alike according to Double Metaphone, and the ratio of Levenshtein distance to match_text length is below 0.2.
To use, pass the output fields "match_text" and "placename" from junk2geo.sh as a TSV to this script use the '-i' flag.

OPTIONS:
   -h      show this message
   -i      input TSV with just two fields: match_text, placename from junk2geo
   -s      input stopword list, one term per line.  building good stopword list is key.
   -b      boxes (hosts) to run this scrip on.  defaults to localhost if none given
   -d      full path to double metaphone script, using https://github.com/slacy/double-metaphone
   -l      full path to levenshtein distance script, using https://github.com/albert-decatur/as-seen-online/blob/master/levenshtein.py

Example use: $0 -i test/nepal/np_matches.tsv -s stopwords/google_1grams_lengthGT2_countGT3000_yearGE1990.tsv -d /opt/double-metaphone/dmtest -l /usr/local/bin/levenshtein.py > metrics.tsv
Note that field headers must literally be "match_text" and "placename".
This is also the junk2geo output default.

EOF
}

while getopts "hi:s:b:d:l:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         i)
             intxt=$OPTARG
             ;;
         s)
             stopwords=$OPTARG
             ;;
         b)
             boxes=$OPTARG
             ;;
         d)
             dm_path=$OPTARG
             ;;
         l)
             lev_path=$OPTARG
             ;;
     esac
done

# define functions used by GNU parallel
function identical { 
	if [[ "$1" == "$2" ]]; then 
		echo 1
	fi
}
export -f identical

function as_whitepunctcase { 
	echo $1 |\
	tr -d "[:punct:]" |\
	sed "s:[ \t]\+::g" |\
	awk "{print tolower(\$0) }"
}
export -f as_whitepunctcase

function as_ascii { 
	echo $1 |\
	tr -d "[:punct:]" |\
	sed "s:[ \t]\+::g" |\
	awk "{print tolower(\$0) }" |\
	iconv -c -f utf8 -t ASCII//TRANSLIT |\
	grep -oE "[A-Za-z]+"
}
export -f as_ascii

function length { 
	echo $1 |\
	tr -d "[:punct:]" |\
	awk "{print length(\$0)}"
}
export -f length

function stopword { 
	regex=$( 
		echo $1 |\
		tr -d "[:punct:]" 
	)
	grep -iE "^$regex$" $stopwords
}
export -f stopword

function levenshtein { 
	$lev_path "$1" "$2"
}
export -f levenshtein

# allow diff_dm to use function extract_dm
function diff_dm { 
	match_text_dm=$( extract_dm 2 )
	placename_dm=$( extract_dm 1 )
	diff_dm=$( 
		wdiff -1 -2 <(echo "$match_text_dm") <(echo "$placename_dm") |\
		grep -vE "^=*$" 
	)
	echo "$diff_dm"
}
export -f diff_dm

# use localhost is -b flag not used
if [[ -z $boxes ]]; then
	# use GNU parallel syntax for localhost
	boxes=:
fi

# print header
echo -e "match_text\tplacename\tidentical\tas_whitepunctcase\tas_ascii\tlength_match\tis_stopword\tlevenshtein_dist\tcount_dm_agree"

cat $intxt |\
# remove slashes for GNU parallel
sed 's:\/::g' |\
parallel --gnu -S "$boxes" --trim n --colsep '\t' --header : '
	# double metaphone function uses field names so keeping inside gnu parallel
	function extract_dm { '$dm_path' <( echo -e "{match_text}\n{placename}" | sed "s:,::g" ) | awk -F, "{OFS=\"\t\";print \$2,\$3}" | sed "$1d" | tr "\t" "\n" ; }
	export -f extract_dm
	# define variables for function outside parallel
	stopwords='$stopwords'
	dm_path='$dm_path'
	lev_path='$lev_path'
	identical=$( identical {match_text} {placename} )
	if [[ -z $identical ]]; then
		identical=0
	else
		# strings are truly identical
		identical=1
	fi

	if [[ $( as_ascii {match_text} ) != $( as_ascii {placename} ) ]]; then 
		as_ascii=0
	else	
		# strings would be identical with no whitespace, no punctuation, and as lowercase AND as ASCII//TRANSLIT [A-Za-z]
		as_ascii=1	
	fi

	if [[ $( as_whitepunctcase {match_text} ) != $( as_whitepunctcase {placename} ) ]]; then 
		as_whitepunctcase=0
	else
		# strings would be identical with no whitespace, no punctuation, and as lowercase
		as_whitepunctcase=1
	fi

	length_match=$( length {match_text} )
	
	if [[ -n $( stopword {match_text} ) ]]; then
		is_stopword=1
	else
		is_stopword=0
	fi

	levenshtein_dist=$( levenshtein {match_text} {placename} )

	count_dm_agree=$( diff_dm | grep -vE "^$" | wc -l )

	echo -e {match_text}"\t"{placename}"\t$identical\t$as_whitepunctcase\t$as_ascii\t$length_match\t$is_stopword\t$levenshtein_dist\t$count_dm_agree"
'
