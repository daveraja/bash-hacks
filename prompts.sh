#-------------------------------------------------------------------------
# prompts.sh
#
# Provides some prompt support functions (using "read -p" as the basis). 
# Simply adds some error correction for things like yes/no prompts.
# These functions should be called using the $(...) form, as they return 
# a value.
#-------------------------------------------------------------------------

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
