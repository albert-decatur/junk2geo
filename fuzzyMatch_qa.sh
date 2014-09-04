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
# NB: makes sense to just use unique match_text / placename combinations with this script and match back later.
# TODO: user provides names of fields, path to levenshtein and double metaphone scripts, field delimiter, localhost assumed if no list of hosts given
# user args: 1) input pipe separated file with the fields 'placename' and 'match_text' **with header**, 2) list of stopwords in any languages, one word per line, 3) comma separated list of hosts to run on with GNU parallel (NB: semicolon is localhost)
# example use: $0 uniq_matches.txt stopwords_en_es_fr_pt.txt :,128.239.103.87,128.239.121.175,grover.itpir.wm.edu,128.239.124.103,cookiemonster.itpir.wm.edu

intxt=$1
stopwords=$2
hosts=$3

# print header
echo "match_text|placename|identical|as_whitepunctcase|as_ascii|length_match|is_stopword|levenshtein_dist|count_dm_agree"

cat $intxt |\
sed 's:\/::g' |\
parallel --gnu -S "$hosts" --trim n --colsep '\|' --header : '
	function identical { if [[ "$1" == "$2" ]]; then echo 1; fi; }
	function as_whitepunctcase { echo $1 | tr -d "[:punct:]" | sed "s:[ \t]\+::g" | awk "{print tolower(\$0) }";}
	function as_ascii { echo $1 | tr -d "[:punct:]" | sed "s:[ \t]\+::g" | awk "{print tolower(\$0) }" | iconv -c -f utf8 -t ASCII//TRANSLIT | grep -oE "[A-Za-z]+";}
	function length { echo $1 | tr -d "[:punct:]" | awk "{print length(\$0)}";}
	function stopword { regex=$( echo $1 | tr -d "[:punct:]" ); grep -iE "^$regex$" '$stopwords'; }
	function levenshtein { /usr/local/bin/levenshtein.py "$1" "$2"; }
	function extract_dm { /opt/double-metaphone/dmtest <( echo -e "{match_text}\n{placename}" | sed "s:,::g" ) | awk -F, "{OFS=\"\t\";print \$2,\$3}" | sed "$1d" | tr "\t" "\n" ; }
	export -f extract_dm
	# allow diff_dm to use function extract_dm
	function diff_dm { match_text_dm=$( extract_dm 2 ); placename_dm=$( extract_dm 1 ); diff_dm=$( wdiff -1 -2 <(echo "$match_text_dm") <(echo "$placename_dm") | grep -vE "^=*$" ); echo "$diff_dm"; }
	function printall { echo {match_text}"|"{placename};}
	
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

	echo $(printall)"|$identical|$as_whitepunctcase|$as_ascii|$length_match|$is_stopword|$levenshtein_dist|$count_dm_agree"
'
