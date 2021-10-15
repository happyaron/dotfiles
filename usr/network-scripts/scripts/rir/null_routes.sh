#!/bin/sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CONF=/etc/bird/bird.d/static/s_nullroute.conf
TMP=$(mktemp)

printer (){
	comment=$1
	shift
	list=$@
	printf "\n\t# Start of entries from $comment\n"
	for x in $list; do
		val=$x
		if ! $(echo $x | grep -q '/'); then val="$x/32"; fi
		printf "\troute $val blackhole;\n"
	done
	printf "\t# End of entries from $comment\n"
}

print_header (){
	printf "# Automatically generated at $(date +"%F %T") CST\n"
	printf "table table_nullroute;\n\n"
	printf "protocol static s_nullroute {\n\ttable table_nullroute;\n"
}

print_footer (){
	printf "}\n"
}


# Sources of the list
get_f2b (){
	list=$(ipset list f2b-sshd -output save| grep add | awk '{print $3}')
	cnt=$(ipset list f2b-sshd -output plain | grep 'Number of entries:' | awk '{print $NF}')
	printer "f2b-sshd" $list
	echo "Collected from f2b, $cnt entries." >&2
}

# Print the conf file
## header
print_header > $TMP
## f2b
get_f2b >>$TMP
## footer
print_footer >> $TMP

cp $TMP $CONF
chmod a+r $CONF
rm -f $TMP
echo "Generated $CONF"

birdc configure
