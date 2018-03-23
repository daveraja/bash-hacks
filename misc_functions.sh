#----------------------------------------------------------------------
# misc_functions.sh
#
# Miscelaneous functions
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# mf_append <string> <string>
#
# Append to the front of an environment variable string. Appends with
# the ':' separator.
# ----------------------------------------------------------------------
mf_concat () {
    if [ "$1" == "" ] || [ "$2" == "" ]; then  # missing elements
	echo "$1$2"
    else
	echo "$1:$2"
    fi
}

#-----------------------------------------------------------------------------------
# mf_in_list <string> <list>
#
# Tests if a string is in a list (where the list is ":" separated) return 1 on false
# and 0 on true.
# ----------------------------------------------------------------------------------
mf_in_list (){
    local string="$1"
    local list="$2"

    if [ "$list" == "" ] || [ "$string" == "" ]; then
	return 1
    fi
    # split the list and search
    local arr=$(echo "$list" | tr ":" "\n")
    for x in $arr
    do
	[ "$x" == "$string" ] && return 0
    done
    return 1
}

mf_list_size (){
    local list="$1"
    if [ "$list" == "" ]; then
	echo 1
    else
	# split the list and search
	count=$(echo "$list" | tr ":" "\n" | wc -l)
	echo $count
    fi
}

# -----------------------------------------------------------------------------
# mf_cond_insert/append <string> <list>
#
# Checks if string is already part of string-list. If it is then just return the
# original list, otherwise return the list with the string inserted(front) /
# appended(back) to the list.
# ------------------------------------------------------------------------------
mf_cond_insert () {
    local string="$1"
    local list="$2"

    if [ "$list" == "" ] || [ "$string" == "" ]; then  # missing elements
	echo "$list$string"
    elif mf_in_list $string $list ; then
	echo "$list"
    else
	echo "$string:$list"
    fi
}

mf_cond_append () {
    local string="$1"
    local list="$2"

    if [ "$list" == "" ] || [ "$string" == "" ]; then  # missing elements
	echo "$list$string"
    elif mf_in_list $string $list ; then
	echo "$list"
    else
	echo "$list:$string"
    fi
}

#-----------------------------------------------------------------------------
# mf_insert/append_if_path <path> <list>
#
# Provided that path exists then conditionally add it to the front/back of the
# path-list (path list is ":" separated). Note: need to account for being passed and
# empty list or empty path (hence the trickiness in the tests).
# ----------------------------------------------------------------------------
mf_insert_if_path () {
    local path="$1"
    local list="$2"

    if ! [ -e "$path" ]; then
	echo "$list"
    else
	echo $(mf_cond_insert "$path" "$list")
    fi
}

mf_append_if_path () {
    local path="$1"
    local list="$2"

    if ! [ -e "$path" ]; then
	echo "$list"
    else
	echo $(mf_cond_append "$path" "$list")
    fi
}


#----------------------------------------------------------------------
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

    local matched=$(who | awk '{print $1}' | sort | uniq | grep "$user")
    if [ "$matched" == "$user" ]; then
	return 0
    fi
    return 1
}


#----------------------------------------------------------------------
# mf_is_remote_shell
#
# Returns 0 (true) if this is a remote shell.
#----------------------------------------------------------------------

mf_is_remote_shell () {
    if [ "$SSH_CLIENT" != "" ]; then
	local ip=$(echo "$SSH_CLIENT" | awk '{print $1}')
	if [ "$ip" == "127.0.0.1" ]; then
	    return 1
	fi
	return 0
    fi
    return 1
}

#-------------------------------
# _mf_is_number
#-------------------------------
mf_is_number() {
    printf '%f' "$1" &> /dev/null
}

