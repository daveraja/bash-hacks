#----------------------------------------------------------------------
# misc_functions.sh
#
# Miscelaneous functions
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# mf_append <string-list> <append-string>
# Takes an environment variable type list and appends to it with ":" as
# the separator.
#----------------------------------------------------------------------
mf_append () {
    if [ "$1" == "" ]; then
	echo "$2"
	return
    fi
    if [ "$2" == "" ]; then
	echo "$1"
	return
    fi
    echo "$1:$2"
}

#----------------------------------------------------------------------
# mf_cond_append <string-list> <append-string>
# Checks if str2
#----------------------------------------------------------------------
mf_cond_append () {
    # Simple cases
    if [ "$1" == "" ]; then
	echo "$2"
	return
    elif [ "$2" == "" ]; then
	echo "$1"
	return
    fi
    local string="$1"
    local append="$2"

    # split the list and search
    local arr=$(echo "$string" | tr ":" "\n")
    for x in $arr
    do
	if [ "$x" == "$append" ]; then
	    echo "$string"
	    return
	fi
    done
    echo "$string:$append"
}

#----------------------------------------------------------------------
# mf_append_sep <string-list> <append-string>
# Takes an environment variable type list and appends to it with the 
# separator character. NOTE: unlike mf_append the behaviour of this
# function is undefined if any parameters are missing. So for example if
# the environment EMPTY_ENV is empty (rather than "") than things go bad.
#
# see http://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
#
# http://stackoverflow.com/questions/228544/how-to-tell-if-a-string-is-not-defined-in-a-bash-shell-script
#
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# mf_which <program> - A wrapper around the which function. Returns 
# empty string if false and non-empty string if true. 
#----------------------------------------------------------------------
mf_which () {
    echo $(which $1 2>/dev/null)
}


#----------------------------------------------------------------------
# mf_user_loggedin <username>
#
# Returns 0 (true) if the user is logged in and 1 (false) otherwise.
#----------------------------------------------------------------------
mf_user_loggedin () {
    local user="$1"
    if [ "$user" == "" ]; then
	echo "$FUNCNAME: No user specified"
	return 1
    fi

    local matched=$(who | awk '{print $1}' | uniq | grep "$user")
    if [ "$matched" == "$user" ]; then
	return 0
    fi
    return 1
}
