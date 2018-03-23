#-------------------------------------------------------------------------
# prompts.sh
#
# Provides some prompt support functions (using "read -p" as the basis).
# Simply adds some error correction for things like yes/no prompts.
# These functions should be called using the $(...) form, as they return
# a value.
#-------------------------------------------------------------------------
mbimport misc_functions

#----------------------
# returns 1 if valid answer and 0 otherwise
#----------------------
_prompt_valid_yesno (){
    local v="$1"
    local save=$(shopt | grep -F nocasematch)
    shopt -s nocasematch # set case insensitive pattern matching
    local re="1"
    if [[ $v != "yes" ]] && [[ $v != "no" ]] && [[ $v != "y" ]] && [[ $v != "n" ]]; then
	re="0"
    fi
    [ "$save" == "off" ] && shopt -u nocasematch  # reset case matching
    [ "$re" == "1" ] && return 0
    return 1
}

#----------------------
# returns "y" or "n" for the input
# Should be called with $(...).
#----------------------
_prompt_normalise_yesno (){
    local val="$1"
    local save=$(shopt | grep -F nocasematch)
    shopt -s nocasematch # set case insensitive pattern matching
    local re=""

    if [[ "$val" =~ ^y(es)?$ ]]; then re="y"
    elif [[ "$val" =~ ^n(o)?$ ]]; then re="n"
    fi
    [ "$save" == "off" ] && shopt -u nocasematch  # reset case matching
    echo "$re"
}

#----------------------------------------------------
# prompt_yesno <question> [default]
# Prompts the user for a yes/no answer to a question.
# Will reprompt until a valid answer is provided.
# Allows for an optional default answer for when
# user presses enter.
#----------------------------------------------------
prompt_yesno () {
    local question="$1"
    local default="$2"
    local answer=""

    if [ "$default" != "" ] && ! _prompt_valid_yesno "$default" ; then
	echo "error: prompt_yesno function invalid default $default" 1>&2
	echo ""
	return
    fi

    read -p "$question " answer
    [ "$answer" == "" ] && answer="$default"
    while ! _prompt_valid_yesno "$answer"; do
	echo "Invalid value $answer. Expecting 'y(es) or n(o)'"
	read -p "$question " answer
	[ "$answer" == "" ] && answer="$default"
    done
    echo $(_prompt_normalise_yesno "$answer")
}

#----------------------------------------------------
# prompt_run <statement>
# A protected way to run a command by forcing the user to
# answer a yes/no prompt.
#----------------------------------------------------
prompt_run () {
    local question="Run command \"$@\" [Y/n]?"
    local result=$(prompt_yesno "$question" "y")
    if [ "$result" == "y" ]; then
	$@
	return $?
    fi
    return 1
}

#----------------------------------------------------
# prompt_input <input>
# Simple prompt for input
#----------------------------------------------------

prompt_input (){
    local question="$*"
    local answer=""
    read -p "$question " answer
    echo $answer
}



#----------------------------------------------------
# prompt_choose
# Prompts the user to select from a number of choices.
# Each choice is numbered. Returns the choice.
#----------------------------------------------------

#_prompt_isnumber() {
#    printf '%f' "$1" &> /dev/null
#}

_prompt_choose() {
    local num_choices=$#
    local choices=()
    local i=1
    for c in "$@"; do
	choices[$i]=$c
	((i++))
    done
    i=1
    while (( i <= num_choices )); do
	option=${choices[$i]}
	echo "${i}) $option" 1>&2
	((i++))
    done
    read -p "Selection: " answr
    if ! mf_is_number $answr; then
	echo "Invalid selection: $answr" 1>&2
	echo ""
	return 0
    fi
    if (( answr <= 0 )) || (( answr > num_choices )); then
	echo "Invalid selection: $answr" 1>&2
	echo ""
	return 0
    fi
    echo "${choices[$answr]}"
    return 0
}

prompt_choose() {
    local num_choices=$#

    # sanity check the number of choices
    if (( num_choices == 0 )); then
	echo "Invalid call to prompt_choices with 0 arguments" 1>&2
	return 1
    elif (( num_choices  == 1 )); then
	echo "$1"
	return 0
    fi

    # Repeat until we get a valid selection
    local choice=""
    while [ "$choice" == "" ]; do
	choice=$(_prompt_choose "$@")
    done
    echo "$choice"
    return 0
}
