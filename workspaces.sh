#-------------------------------------------------------------------------
# workspaces.sh
#
# Provides functions to setup and control workspaces. A workspace is simply
# a directory containing some special files. It is a bit heavy handed and
# implements workspaces by running a sub-bash shell. This ensures that
# switching workspaces don't polute each others environment spaces.
# Following are the environment variables and special files that are
# used by this package.
#
# Special files/directories:
# - local: In the directory that is a workspace a
# - ./.workspace - directory is created. This directory contains:
#     - on_enter.sh  - file that is run on workspace startup
#     - on_exit.sh   - file that is run on workspace exit
#     - bash_history - use this file to maintain the bash history.
#     - id.<NNNN>    - randomly generated unique identify for workspace.
#     - pids.tmp     - temporary file containing process id of active
#                      workspace shells.
# - ~/.workspaces - Contains symlinks to all registered workspaces
#
# Environment variables that are used.
# - WORKSPACE_DIR - A workspace HOME directory.
# - WORKSPACE_ID - A workspace identifier, from the workspace id file.
# - WORKSPACE_LEVEL - Level of stacked workspaces.
# - WORKSPACE_TMPFILE - A temporary file for starting and cleaning up
#                       stacked workspace.
# - WORKSPACE_BASH_ROOT_PID - The PID of the workspace root.
# - WORKSPACES_HOOK_ON_ENTER - An array of handlers to be called
#                              before on_enter.sh is run.
# - WORKSPACES_HOOK_ON_EXIT - An array of handlers to be called
#                             after on_exit.sh has been run.
#
# The idea is to maintain symlinks to workspaces so that we can
# quickly list and go to them using tab completion.
#
# Main user callable command functions:
# 1) wksp <cmd> <args> - run "wksp help" for more information.
# 2) ws   - shortcut for "wksp chg"
# 3) wsls - shortcut for "wksp ls". "ls" relative to WORKSPACE_DIR.
# 4) wscd - shortcut for "wksp cd". "cd" relative to WORKSPACE_DIR.
#
#
# Workspaces allow for a simple extension mechanism. An extension
# module can call the wksps_hook_on_enter() and wksps_hook_on_exit()
# functions to setup handlers that are then called before
# on_enter.sh and after on_exit.sh respectively. Note: once an
# extension has been attached, it cannot be detached.

# Prerequisites: assumes readlink and sed are installed.
#
# Bug/clean-up notes:
# 1) Initially I thought of allowing workspaces to be pushed and popped
#    off a stack. In hindsight I don't see any particular reason for this,
#    so the code contains a mix of the push/pop stuff (eg., the use of a
#    WORKSPACE_LEVEL env variable) as well as a simpler  load/unload model.
#    So should clean this up and simplify things at some point.
# 2) Do a better job of understanding how the completions works. I'm sure
#    that there must be some tricks that would simplify things a lot.
#    Especially in terms of using aliases instead of short version functions.
# 3) bug: completion for "wksp ls|cd" doesn't works as well as "wsls|wscd".
# 4) Currently have to load workspaces.sh after any "ls" aliases have been
#    setup, otherwise things like coloring of entries won't work. Should
#    be possible to do this properly.
#
# Fixes:
# 20160615 - Problem with workspace sub-shells not being setup correctly
#            because they won't inherit the bash functions that were setup
#            with the workspace on_enter.sh file. Proposed solution is to
#            modify the load_if function to detect if it is a sub-shell
#            and if so to source the workspace's on_enter.sh.
#
#----------------------------------------------------------------------
mbimport prompts

#-----------------------------------------------------------------------
# Generic internal functions
#-----------------------------------------------------------------------

#------------------------------
# _wksps_init
# - Call this to make sure things are setup correctly
#------------------------------
_wksps_init (){
    if [ ! -d ~/.workspaces ]; then
	echo "Creating workspaces link directory: ~/.workspaces"
	mkdir ~/.workspaces
    fi
}
#export -f _wksps_init

#------------------------------
# _wksps_get_abs_name <directory>
# - return an absolute or if it is HOME relative then ~.
# (e.g., /usr/local/hello or ~/hello)
#------------------------------

_wksps_get_abs_name (){
    local cleaned=$(echo "$*" | sed -e 's!^~\(.*\)$!'"$HOME"'/\1!')
#    local absws=$(readlink -m "$*")
    local absws=$(readlink -m "$cleaned")
    echo "$absws"
}
#export -f _wksps_get_abs_name

_wksps_get_tilda_name (){
    local absws=$(readlink -m "$*")
    local cleanws

    cleanws=$(echo "$absws" | sed -e 's!^'"$HOME"'\(.*\)$!~\1!')
    echo "$cleanws"
}
#export -f _wksps_get_tilda_name

#------------------------------
# _wksps_args
# Pass variables through:
# <cmd> `_wksps_args <first_index> "$@"`
# @param Index of first argument to pass through
# @param List of parameters
#
# taken from - https://github.com/stianlik/bash-workspace/blob/master/workspace.sh
#------------------------------

_wksps_args() {
    local i=1
    local min=$(( $1 + 1 ))
    for var in "$@"; do
	i=$(( $i + 1 ))
        if [ $i -gt $min ]; then echo $var; fi
    done;
}
#export -f _wksps_args

#------------------------------
# _wksps_args_is_option
# skip optional arguments (anything starting with '-')
#------------------------------

_wksps_args_is_option() {
    if [[ "$@" =~ /- ]]; then
	return 0
    fi
    return 1
}
#export -f _wksps_args_is_option


#-----------------------------------------------------------------------
# Internal functions for creating and loading workspaces
#-----------------------------------------------------------------------

#------------------------------
# _wksps_mk_local_ws_dir <workspace>
#------------------------------

_wksps_mk_local_ws_dir (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$*")
    if [ ! -d $absws ]; then
	echo "error: not a directory: $ws"
	return 1
    fi
    if [ ! -d "$absws/.workspace" ]; then
	mkdir "$absws/.workspace"
    fi
    return 1
}
#export -f _wksps_mk_local_ws_dir

#------------------------------
# _wksps_create_ws_id, _wksps_get_ws_id, _wksps_load_ws_id   <workspace>
# Create a workspace ID file
# Get the workspace ID file
# Load a workspace ID
#------------------------------

_wksps_random_id (){
    RANDOM=$(date +%s)
    local r1=$(printf "%05d" $RANDOM)
    local r2=$(printf "%05d" $RANDOM)
    echo "$r1$r2"
}
#export -f _wksps_random_id

_wksps_get_ws_id (){
    local ws="$*"
    local id
    id=$(ls "$ws"/.workspace/id.* 2>/dev/null | head -n 1 | sed -n 's/^.*\.workspace\/id\.\(.*\)$/\1/p')
    echo "$id"
}
#export -f _wksps_get_ws_id

_wksps_get_ws_pidsfile (){
    local ws="$*"
    local pidsfile
#    local id
#    id=$(ls "$ws"/.workspace/id.* 2>/dev/null | head -n 1 | sed -n 's/^.*\.workspace\/id\.\(.*\)$/\1/p')
#   echo "$ws/.workspace/id.$id"
    echo "$ws/.workspace/pids.tmp"
}
#export -f _wksps_get_ws_id


_wksps_create_ws_id (){
    local ws="$*"
    local id
    id=$(_wksps_get_ws_id "$ws")
    if [ "$id" != "" ]; then
	echo "warning: workspace already contains an ID file: $ws"
	return 0
    fi
    id=$(_wksps_random_id)
    _wksps_mk_local_ws_dir "$ws"
    touch "$ws/.workspace/id.$id"
    return 0
}
#export -f _wksps_create_ws_id


_wksps_load_ws_id (){
    local ws="$*"
    local id
    [ ! -d "$ws"/.workspace ] && return

    id=$(_wksps_get_ws_id "$ws")
    if [ "$id" == "" ]; then
	if ! _wksps_create_ws_id "$ws"; then
	    echo "error: failed to create and load a workspace ID file"
	    return 1
	fi
	id=$(_wksps_get_ws_id "$ws")
    fi
    export WORKSPACE_ID=$id
    return 0
}
#export -f _wksps_load_ws_id

#-------------------------------
# _wksps_cleanup_inactive_pids ()
# Clean up the workspace id file to only include active entries
#-------------------------------
_wksps_cleanup_inactive_pids (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$ws")
    local pidsfile=$(_wksps_get_ws_pidsfile "$absws")
    local activelist=()
    local pid

    if [ ! -f "$pidsfile" ]; then
	touch "$pidsfile"
	return 0
    fi

    while read pid; do
	if [[ $pid =~ [0-9]+ ]]; then
	    local result=$(ps --no-headers $pid)
	    if [ "$result" != "" ]; then
		activelist[${#activelist[*]}]=$pid
	    fi
	fi
    done < "$pidsfile"

    # Now writeout the active list
    > "$pidsfile"
    for pid in "${activelist[@]}"; do
	echo $pid >> "$pidsfile"
    done

    # If the file is empty then remove it
    [ ! -s "$pidsfile" ] && rm "$pidsfile"
}
#export -f _wksps_cleanup_inactive_pids


#-------------------------------
# Returns the number of active pids for the workspace
# wksps_num_active_pids <directory>
#-------------------------------

_wksps_num_active_pids ()
{
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$ws")
    local pidsfile=$(_wksps_get_ws_pidsfile "$absws")
    local activelist=()
    local pid

    if [ ! -f "$pidsfile" ]; then
	echo "0"
	return 0
    fi

    while read pid; do
	if [[ $pid =~ [0-9]+ ]]; then
	    activelist[${#activelist[*]}]=$pid
	fi
    done < "$pidsfile"
    echo "${#activelist[*]}"
}
#export -f _wksps_num_active_pids

#------------------------------
# _wksps_create_ws_history, _wksps_load_ws_history <workspace>
# Create a workspace history file
# Load a workspace history file
#------------------------------

_wksps_create_ws_history (){
    local ws="$*"
    local wshistory="$*/.workspace/bash_history"
    if [ -f "$wshistory" ]; then
	echo "warning: workspace already contains a history file: $ws"
	return 0
    fi
    _wksps_mk_local_ws_dir "$ws"
    touch "$wshistory"
    return 0
}
#export -f _wksps_create_ws_history

_wksps_load_ws_history (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$*")
    local wshistory="$absws/.workspace/bash_history"

    [ ! -d "$absws/.workspace" ] && return

    if [ ! -f "$wshistory" ]; then
	_wksps_create_ws_history "$ws"
    fi

#    history -w      # write the current history
    export HISTFILE="$wshistory"
    history -c      # clear history
    history -r      # read new history file
    return 0
}
#export -f _wksps_load_ws_history


#-------------------------------
# _wksps_create_ws_scripts <directory>
# - Create a workspace startup file
# - Load a workspace startup file
#-------------------------------
_wksps_create_ws_scripts (){
    local ws="$*"
    local on_enter="$*/.workspace/on_enter.sh"
    local on_exit="$*/.workspace/on_exit.sh"

    _wksps_mk_local_ws_dir "$ws"
    if [ -f "$on_enter" ]; then
	echo "warning: workspace on_enter script already exists in: $ws"
    else
	cat > "$on_enter" <<EOF
# Workspace configuration file.
# Some variables that you can use:
# - WORKSPACE_ID  - the workspace unique identifier
# - WORKSPACE_DIR - location of this workspace
# Additionally the function "wksps_num_active_pids" returns the
# number of active base shells for this workspace. This is useful
# if you want to run a program (eg., some background daemon) to be
# shared by all instances of the workspace.
local npids=\$(wksps_num_active_pids)
echo "Setting up workspace[\$npids]..."
EOF
    fi
    if [ -f "$on_exit" ]; then
	echo "warning: workspace on_exit script already exists in: $ws"
    else
	cat > "$on_exit" <<EOF
# Workspace clean file. Can use the WORKSPACE_ID, WORKSPACE_DIR variables
# as in the startup file. 
# Note: 1) any configuration that was setup in the on_enter.sh script will
#          be gone by the time we get here.
#       2) The "wksps_num_active_pids" returns the number of active shells
#          not including this one. So if this is cleaning up the last active
#          shell for the workspace then "wksps_num_active_pids" will return 0.
local npids=\$(wksps_num_active_pids)
if [ \$npids -eq 0 ]; then
   echo "Cleaning up workspace..."
fi
EOF
    fi

    return 0
}
#export -f _wksps_create_ws_scripts

_wksps_load_ws_on_enter_script (){
    local ws="$*"
    local wsfile="$*/.workspace/on_enter.sh"

    [ ! -f "$wsfile" ] && return 1
    source "$wsfile"
    return 0
}
#export -f _wksps_load_ws_on_enter_script

#-------------------------------
# _wksps_is_common_ws, _wksps_mk_common_ws, _wksps_delws_common_ws  <workspace>
# - check if the workspace is a common ws
# - make the workspace a common ws
# - remove the workspace from the common ws
#-------------------------------

#-------------------------------
# _wksps_create_ws_link, _wksps_remove_ws_link <directory>
# - create the symlink for the workspace
#-------------------------------
_wksps_create_ws_link (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$*")
    id=$(_wksps_get_ws_id "$ws")

    if [ "$id" == "" ]; then
	echo "error: not a workspace, missing id file: $ws"
	return
    fi
    ln -s "$absws" ~/.workspaces/$id
}
#export -f _wksps_create_ws_link

_wksps_remove_ws_link (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$*")
    id=$(_wksps_get_ws_id "$ws")

    if [ "$id" == "" ]; then
	echo "error: not a workspace, missing id file: $ws"
	return
    fi
    rm -f ~/.workspaces/$id
}
#export -f _wksps_remove_ws_link

#-------------------------------
# _wksps_has_ws_link ()
# - Check if the workspace has a link
#-------------------------------
_wksps_has_ws_link (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$*")
    local found=$(ls -l ~/.workspaces/ | grep "$absws")
    [ "$found" != "" ]
}
#export -f _wksps_has_ws_link

#-------------------------------
# _wksps_is_ws <directory>
# returns 0 if the directory is a workspace
# (ie., has a .workspace.sh and workspace id file, and a ws link)
# or 1 otherwise.
#-------------------------------
_wksps_is_ws (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$ws")
    local id=$(_wksps_get_ws_id "$absws")

    if [ ! -d "$absws" ]; then
	echo "warning: directory does not exist: $ws"
	return 1
    fi

    if [ ! -d "$absws/.workspace" ]  || [ "$id" == "" ]; then
	return 1
    fi
    if ! _wksps_has_ws_link "$absws" ; then
	return 1
    fi
    return 0
}
#export -f _wksps_is_ws


#-------------------------------
# _wksps_in_ws <directory>
# Is this workspace currently loaded
#-------------------------------
_wksps_in_ws (){
    local ws="$*"
    local id=$(_wksps_get_ws_id "$*")

    [ "$WORKSPACE_ID" == "$id" ]
}
#export -f _wksps_in_ws

#-------------------------------
# _wksps_load_ws <workspace>
# - Load a workspace (setting the appropriate env variable)
#-------------------------------
_wksps_load_ws (){
    local ws="$*"
    local absws=$(_wksps_get_abs_name "$*")
    local pidsfile=$(_wksps_get_ws_pidsfile "$absws")

    if ! _wksps_is_ws "$absws" ; then
	echo "error: not a workspace: $ws"
	return 1
    fi

    # Setup the environment
    export WORKSPACE_BASH_ROOT_PID=$$
    if [ -z "$WORKSPACE_LEVEL" ]; then
	export WORKSPACE_LEVEL=0
    else
	export WORKSPACE_LEVEL=$(($WORKSPACE_LEVEL+1))
    fi
    export WORKSPACE_DIR="$absws"

    # Add the current workspace bash shell to the active PID list
    echo "$WORKSPACE_BASH_ROOT_PID" >> "$pidsfile"

    # Set things up
    _wksps_load_ws_id "$absws"
    _wksps_load_ws_history "$absws"

    # Run the workspaces on_enter hooks
    for hook in "${WORKSPACES_HOOK_ON_ENTER[@]}"; do
	eval "$hook"
    done

    # Call the user on_enter script
    _wksps_load_ws_on_enter_script "$absws"
}
#export -f _wksps_load_ws

#-------------------------------
# _wksps_set_ws_cleanup_fn <string>
# This function is run from within the workspace temp startup file
#-------------------------------
_wksps_set_ws_cleanup_fn (){
    if [ "$WORKSPACE_TMPFILE" == "" ]; then
	echo "error: no WORKSPACE_TMPFILE variable defined"
	return 1
    fi

    # We want to know the pid of the workspace shell from the calling shell
    echo "export WORKSPACE_BASH_ROOT_PID=$$" > $WORKSPACE_TMPFILE

    # Create a results function
    echo "_wksps_tmp_run_cleanup_fn () {" >> $WORKSPACE_TMPFILE
    echo "$*" >> $WORKSPACE_TMPFILE
    echo "}" >> $WORKSPACE_TMPFILE
    return 0
}

#export -f _wksps_set_ws_cleanup_fn


#-------------------------------
# _wksps_get_all
# - Get the list of workspaces by setting the value of a
#   known global array. WORKSPACES
#-------------------------------

_wksps_get_all (){
    local fn
    local ws
    WORKSPACES=()
    for fn in ~/.workspaces/*; do
	if [ -h "$fn" ]; then
	    ws=$(_wksps_get_tilda_name $(readlink "$fn"))
	    WORKSPACES[${#WORKSPACES[@]}]="$ws"
	fi
    done
}
#export -f _wksps_get_all

#-----------------------------------------------------------------------
# Functions corresponding to the main commands
#-----------------------------------------------------------------------


#-------------------------------
# wksps_push <workspace>
# Push a workspace on to the workspace stack.
# Only call this directly if you know what you are doing.
#-------------------------------

_wksps_push () {
    local currdir=$(pwd)
    local newws=$(readlink -m "$*")
    local unsetlevel=0
    local savedwstmpfile="$WORKSPACE_TMPFILE"
    local cleanupfn

    # Save state of the current environment so we can
    # recover properly after the workspace is popped
    if [ -z "$WORKSPACE_LEVEL" ]; then
	unsetlevel=1
	export WORKSPACE_LEVEL=0
    fi

    # Make sure that we are talking about a workspace
    if ! _wksps_is_ws "$newws" ; then
	echo "error: not a workspace: $newws"
	return
    fi

    # A temporary file for communicating with the new shell workspace
    export WORKSPACE_TMPFILE=$(mktemp "/tmp/${USER}_tmpws.XXXXXXXXX")

    # Go to the new workspace dir, load the workspace, set a default
    # cleanup function, then source ~/.bashrc. Note: default cleanup
    # is necessary for Ctrl-D (EOF) to exit properly.
    echo "source ~/.bashrc" > $WORKSPACE_TMPFILE
    echo "cd \"$newws\"" >> $WORKSPACE_TMPFILE
    echo "_wksps_load_ws ." >>  $WORKSPACE_TMPFILE
    echo "_wksps_set_ws_cleanup_fn \"exit\"" >> $WORKSPACE_TMPFILE

    # Set up WORKSPACE_ID  and WORKSPACE_DIR
    export WORKSPACE_ID=$(_wksps_get_ws_id "$newws")
    export WORKSPACE_DIR="$newws"

    # Make the workspace directory the current directory for the
    # non-workspace parent shell. This will make opening a new
    # shell from this parent more intuitive.
    builtin cd "$newws"

    # Load and enter the new workspace
    bash --rcfile $WORKSPACE_TMPFILE

    # Reload the workspace tmpfile. This defines the cleanup function and
    # the PID of the (now exited) workspace shell.
    if [ -f "$WORKSPACE_TMPFILE" ]; then
	source "$WORKSPACE_TMPFILE"
	rm -f "$WORKSPACE_TMPFILE"
    fi

    # Remove the PID from the active list in the workspace id file
    _wksps_cleanup_inactive_pids "$newws"

    # Now run the on_exit script
    if [ -f "$newws/.workspace/on_exit.sh" ]; then
	source "$newws/.workspace/on_exit.sh"
    fi

    # Finally run any extension hooks
    for hook in "${WORKSPACES_HOOK_ON_EXIT[@]}"; do
	eval "$hook"
    done


    # Recover from the
    unset WORKSPACE_ID
    unset WORKSPACE_DIR
    unset WORKSPACE_BASH_ROOT_PID

    # Recover from the pop/exit/switch
    if [ $unsetlevel -eq 1 ]; then
	unset WORKSPACE_LEVEL
    fi

    # Now run the cleanup function
    cleanupfn=$(declare -f "_wksps_tmp_run_cleanup_fn")
    if [ "$cleanupfn" != "" ]; then
	_wksps_tmp_run_cleanup_fn
	unset -f _wksps_tmp_run_cleanup_fn
    fi

    # The clean up has been performed
    if [ $unsetlevel -eq 1 ]; then
	unset WORKSPACE_TMPFILE
    else
	export WORKSPACE_TMPFILE="$savedwstmpfile"
    fi
    builtin cd "$currdir"
}
#export -f _wksps_push

#-------------------------------
# wksps_pop - Pop a stacked workspace
# Only call this directly if you know what you are doing.
#-------------------------------
_wksps_pop () {
    if [ -z "$WORKSPACE_LEVEL" ] || [ $WORKSPACE_LEVEL -eq 0 ]; then
	echo "no loaded workspaces" 1>&2
	return 1
    fi
    # Can only unload from a workspace bash root
    if wksps_is_subshell ; then
	echo "cannot unload a workspace from a workspace sub-shell"
	return 1
    fi
    _wksps_set_ws_cleanup_fn ":"
    builtin exit &>/dev/null
}
#export -f _wksps_pop


#-------------------------------
# wksps_reload
# Reload a workspace
#-------------------------------
_wksps_reload () {
    if [ "$WORKSPACE_DIR" == "" ]; then
	echo "No workspace loaded" 1>&2
	return 1
    fi

    # Can only switch workspaces from the workspace bash root
    if wksps_is_subshell ; then
	echo "cannot reload workspace: unable to unload workspace from a workspace sub-shell"
	return 1
    fi
    echo "Reloading workspace..." 1>&2
    # Reload workspace means exiting the current shell also but setting up so
    # the parent shell will re-startup the workspace.
    _wksps_set_ws_cleanup_fn "_wksps_push \"$WORKSPACE_DIR"\"
    builtin exit &>/dev/null
    return 0
}

#-------------------------------
# wksps_mk ()  - make a workspace
#-------------------------------
_wksps_mk (){
    local ws="$*"

    if _wksps_is_ws "$ws" ; then
	echo "error: already a workspace: $ws"
	return 1
    fi
    _wksps_create_ws_scripts "$ws"
    _wksps_create_ws_id "$ws"
    _wksps_create_ws_history "$ws"
    _wksps_create_ws_link "$ws"
    return 0
}
#export -f _wksps_mk


#-------------------------------
# _wksps_isnumber
#-------------------------------
_wksps_isnumber() {
    printf '%f' "$1" &> /dev/null
}

#-------------------------------
# _wksps_selws_prompt
# Prompt the user to select a workspace from a list
#-------------------------------

_wksps_selws_prompt (){
    local wrksps_u=()
    local wrksps_s=()
    local tmpi
    local prompt="$@"

    # Build the list of workspace symlinks that point to valid directories.
    for fn in ~/.workspaces/*; do
	if [ -h "$fn" ] && [ -d "$fn" ] ; then
	    wrksps_u[${#wrksps_u[@]}]=$(_wksps_get_tilda_name $(readlink "$fn"))
	fi
    done

    # Display the sorted list with a number for each selection
    for fn in $(for i in ${wrksps_u[@]}; do echo "$i"; done | sort) ; do
	tmpi=$(( ${#wrksps_s[@]} + 1))
	wrksps_s[${#wrksps_s[@]}]=$fn
	echo "$tmpi) $fn" 1>&2
    done

    # Read/validate/return the answer
    read -p "$@" answr
    if ! _wksps_isnumber $answr; then
	echo "error: not a number: $answr" 1>&2
	echo ""
    elif [ $answr -gt 0 ] && [ $answr -le ${#wrksps_s[@]} ]; then
	tmpi=$(( $answr - 1 ))
	echo "${wrksps_s[$tmpi]}"
    else
	echo "error: out of range selection: $answr" 1>&2
	echo ""
    fi
}


#-------------------------------
# _wksps_chgws_prompt
# Prompt the user to select a workspace from a list then
# change to that workspace.
#-------------------------------
_wksps_chgws_prompt (){
    local res=""
    while [ "$res" == "" ]; do
	res=$(_wksps_selws_prompt "Select workspace: ")
    done
    res=$(_wksps_get_abs_name "$res")
    _wksps_chgws "$res"
}


#-------------------------------
# _wksps_mk_prompt <directory>
# Prompts the user to create a workspace in a directory, then
# create a workspace file.
#-------------------------------
_wksps_mk_prompt (){
    local ws="$*"
    local go

    # If no options specified assume the current directory
    if [ "$ws" == "" ]; then
	ws="$(pwd)"
    fi

    local absws=$(_wksps_get_abs_name "$ws")

    if _wksps_is_ws "$absws" ; then
	echo "error: already a workspace: $absws"
	return 1
    fi

    read -p "Setup as workspace: $absws ? " yn
    case $yn in
	[Yy]* ) go=1 ;;
	*) go=0 ;;
    esac
    if [ $go -eq 1 ]; then
	echo "Creating workspace: $absws"
	_wksps_mk "$absws"
	return 0
    fi
    return 1
}
#export -f _wksps_mk_prompt

#-------------------------------
# wksps_chgws () - change workspace
# Goto/change/create the workspace
# - if no arguments then go to the current workspace
#-------------------------------
_wksps_chgws () {
    local goto_ws=1
    local ws="$*"
    local absws=$(readlink -m "$*")

   # No arguments
    if [ $# -eq 0 ]; then
	if [ "$WORKSPACE_DIR" == "" ]; then
	    _wksps_chgws_prompt
	    return 0
#	    echo "WORKSPACE_DIR is not set" 1>&2
#	    return 1
	fi
	builtin cd "$WORKSPACE_DIR"
	return
    elif ! _wksps_is_ws "$absws" ; then
	echo "error: not a workspace: $ws"
	if [ -d "$ws" ]; then
	    echo "use 'wksp add' to make this directory a workspace"
	fi
	return 1
#	if ! _wksps_mk_prompt "$ws" ; then
#	    goto_ws=0
#	fi
    fi
    if [ $goto_ws -eq 1 ]; then
	if [ "$WORKSPACE_ID" == "" ]; then                          #  Load new workspace
	    _wksps_push "$absws"
	elif [ -f "$absws/.workspace/id.$WORKSPACE_ID" ]; then      # Same workspace so simply cd
	    builtin cd "$WORKSPACE_DIR"
	else
            # Switch workspaces means exiting the current shell but setting up so
	    # the parent shell will startup the new workspace.
	    # But can only switch workspaces from the workspace bash root
	    if wksps_is_subshell ; then
		echo "cannot switch workspaces: unable to unload workspace from a workspace sub-shell"
		return 1
	    fi
#	    echo "switching workspaces..."
	    _wksps_set_ws_cleanup_fn "_wksps_push \"$absws"\"
	    builtin exit &>/dev/null
	fi
    fi
    return 0
}
#export -f _wksps_chgws

#-------------------------------
# wksps_listws
# - list workspaces
#-------------------------------
_wksps_listws (){
    local ws
    _wksps_get_all
    for ws in ${WORKSPACES[@]}; do
	echo "$ws"
    done
}
#export -f _wksps_listws

#-------------------------------
# wksps_delws <directory>
# - Delete a workspace.
#   Note: this only deletes the symlink. Delete the
#   directory manually.
#-------------------------------
_wksps_delws () {
    local ws="$*"

    if ! _wksps_is_ws "$ws" ; then
	echo "error: not a workspace: $ws"
	return 1
    fi
    if _wksps_in_ws "$ws"; then
	echo "error: must unload before deleting the currently loaded workspace: $ws"
	return 1
    fi

    _wksps_remove_ws_link "$ws"
    echo "workspace link has been deleted. Please delete directory to fully remove data: $ws"
    return 0
}
#export -f _wksps_delws

#---------------------------------
# wksps_load_if ()
# Two checks:
# 1) If we're in a sub-shell then source the workspace's on_enter.sh.
# 2) if no workspace is active and the current directory is a workspace.
#    If so then by default calls wspush to load the new workspace, or
#    optionally (the "-p" option) prompts the user.
#---------------------------------
_wksps_load_if () {
    # If already in a workspace then check if a subshell needs to source on_enter.sh
    if wksps_is_loaded ; then
	if ! wksps_is_subshell ; then
	    return 0
	fi
	_wksps_load_ws_on_enter_script "$WORKSPACE_DIR"
	return 0
    fi

    # If not currently in a workspace then load if
    local currdir=$(pwd)
    local options="$*"
    if ! _wksps_is_ws "$currdir" ; then return 0; fi

    if [ "$options" != "-p" ] && [ "$options" != "" ]; then
	echo "error: Invalid options '$options' for load_if"
	return 1
    fi
    # prompt if we really want to load the workspace
    if [ "$options" == "-p" ]; then
	echo "Current directory: $currdir"
	local res=$(prompt_yesno "Load workspace in this directory (Y/n)" y)
	[ "$res" == "n" ] && return 0
    fi
    _wksps_push "$currdir"
}
#export -f _wksps_load_if


#---------------------------------
# wksps_cleanup ()
# Checks to make sure all workspaces are valid. If the symlink doesn't
# point to a valid directory then prompt the user to remove it.
#---------------------------------
_wksps_cleanup () {
    for idfile in ~/.workspaces/*; do
	if [ -h "$idfile" ]; then
	    local absws=$(readlink -m "$idfile")
	    local ws=$(_wksps_get_tilda_name "$absws")

	    # Check if we have a deletion candiate - prompt to delete
	    if [ ! -d "$absws" ] || [ ! -d "$absws/.workspace" ] ; then
		if [ -d "$absws" ] && [ ! -d "$absws/.workspace" ] ; then
		    echo "Directory exists but is not a valid workspace: $ws"
		elif [ ! -d "$absws" ] ; then
		    echo "Directory does not exists: $ws"
		fi
		local res=$(prompt_yesno "Do you want to delete this workspace link (y/N)" n)
		if [ "$res" == "y" ]; then
		    echo "Removing stale workspace link: $ws"
		    rm -f $idfile
		fi
	    fi
	fi
    done
}
#export -f _wksps_cleanup

#---------------------------------
# wksps_ls, wksps_cd
# Workspace relative file manipulation functions
#---------------------------------
_wksps_ls () {
    if [ "$WORKSPACE_DIR" == "" ]; then
	echo "WORKSPACE_DIR is not set" 1>&2
	return 1
    fi
    pushd "$WORKSPACE_DIR" 1>&2 > /dev/null
    ls $*
    popd 1>&2 > /dev/null
}
#export -f _wksps_ls

_wksps_cd () {
    local dir="$*"
    if [ "$WORKSPACE_DIR" == "" ]; then
	echo "WORKSPACE_DIR is not set" 1>&2
	return 1
    fi
    if [[ "$dir" =~ ^/ ]] || [[ "$dir" =~ ^~ ]] ; then
	cd "$dir"
    else
	cd "$WORKSPACE_DIR/$dir"
    fi
}
#export -f _wksps_cd

#---------------------------------
# _wksps_cfg
# Configure the current workspace's on_enter and on_exit scripts.
#---------------------------------

_wksps_cfg (){
    local ws="$*"
    local wsdir="$WORKSPACE_DIR/.workspace"
    local editor=$EDITOR
    if [ "$ws" == "" ] && [ "$WORKSPACE_DIR" == "" ]; then
	echo "error: no workspace has been specified or loaded" 1>&2
	return 1
    elif [ "$ws" != "" ]; then
	if ! _wksps_is_ws "$ws" ; then
	    echo "error: $ws is not a valid workspace" 1>&2
	    return 1
	fi
	wsdir="$ws/.workspace"
    fi
    [ "$editor" == "" ] && editor=vi
    $editor $wsdir/on_enter.sh $wsdir/on_exit.sh
}

#---------------------------------
# wksps_help ()
# Show help information
#---------------------------------
_wksps_help () {
    echo "Usage: $1 <COMMAND>"
    echo
    echo "Available commands:"
    echo "list             List available workspaces."
    echo "chg [NAME]       Change workspace. If NAME is omitted go to root of current workspace."
    echo "sel              Change workspace by selecting from a list."
    echo "cfg [NAME]       Configure workspace scripts. If NAME is omitted then edit configuration of current workspace."
    echo "add [NAME]       Make the named directory a workspace."
    echo "del [NAME]       Delete a workspace. This deletes the workspace link and the actual directory."
    echo "unload           Unloaded the currently active workspace."
    echo "reload           Reload the currently active workspace. Useful when the configuration has changed."
    echo "load_if [-p]     If the current directory is a workspace then load it. If the option -p is supplied"
    echo "                 then the user is prompted whether to load the workspace (useful for shell startup)."
    echo "cleanup          Remove stale links to workspaces."
    echo "ls | cd          Workspace relative ls and cd operators."
    echo "help             this help information."
}
#export -f _wksps_help


#-----------------------------------------------------------------------
# Internal completion functions
#-----------------------------------------------------------------------

#-------------------------------
# wksps_completion_list
# - list workspaces based on context of a partial completion
#   easy if partial is absolute, trickier if partial is relative path.
#-------------------------------
_wksps_completion_list (){
    local cur="$*"

    if [ "$cur" == "" ] || [[ "$cur" =~ ^/ ]]; then
	echo $(_wksps_listws)
    else
	local abscur=$(readlink -m "$cur")
	if [ -d "$cur" ]; then
	    if [[ ! "$cur" =~ /$ ]]; then cur="$cur/"; fi
	    abscur="$abscur/"
	fi
	echo "$(_wksps_listws | sed -e 's!~!'"$HOME"'!' | sed -n 's!'"$abscur"'!'"$cur"'!p')"
    fi
}
#export -f _wksps_completion_list

#-------------------------------
# wksps_wksp_ls_completion
# - list workspaces based on context of a partial completion
#   easy if partial is absolute, trickier if partial is relative path.
#-------------------------------
_wksps_wksp_ls_completion (){
    local cur="$*"
    local match=()
    local prefix
    local removewsdir=1
    if [ "$cur" == "" ]; then
	prefix="$WORKSPACE_DIR/"
    elif [[ "$cur" =~ ^/ ]] || [[ "$cur" =~ ^~ ]] ; then
	prefix="$cur"
	removewsdir=0
    else
	prefix="$WORKSPACE_DIR/$cur"
    fi
    if [ -d "$prefix" ] && [[ ! "$prefix" =~ /$ ]]; then
	prefix="$prefix/"
    fi
    for fn in "$prefix"*; do
	[ ! -e "$fn" ] && continue
	[ -d "$fn" ] && fn="$fn/"
	if [ $removewsdir -eq 1 ]; then
	    echo $(echo "$fn" | sed -n 's!'"$WORKSPACE_DIR/"'!!p')
	else
	    echo "$fn"
	fi
    done
}
#export -f _wksps_wksp_ls_completion

#-------------------------------
# wksps_wksp_cd_completion
#-------------------------------
_wksps_wksp_cd_completion (){
    local cur="$*"
    local match=()
    local prefix
    local removewsdir=1
    if [ "$cur" == "" ]; then
	prefix="$WORKSPACE_DIR/"
    elif [[ "$cur" =~ ^/ ]] || [[ "$cur" =~ ^~ ]] ; then
	prefix="$cur"
	removewsdir=0
    else
	prefix="$WORKSPACE_DIR/$cur"
    fi
    if [ -d "$prefix" ] && [[ ! "$prefix" =~ /$ ]]; then
	prefix="$prefix/"
    fi
    for fn in "$prefix"*; do
	[ ! -e "$fn" ] && continue
	if [ -d "$fn" ]; then
	    fn="$fn/"
	    if [ $removewsdir -eq 1 ]; then
		echo $(echo "$fn" | sed -n 's!'"$WORKSPACE_DIR/"'!!p')
	    else
		echo "$fn"
	    fi
	fi
    done
}
#export -f _wksps_wksp_cd_completion



#-------------------------------
# _wksps_wksp_autocomplete () completion for wksp command
#-------------------------------

_wksps_wksp_autocomplete () {
    local suggestions
    local cur cmd

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    cmd="${COMP_WORDS[1]}"
    suggestions=""
    if [ $COMP_CWORD -eq 1 ]; then
	suggestions="chg sel cfg add del list load unload reload load_if cleanup help ls cd"
    elif [ $COMP_CWORD -eq 2 ]; then
	if [ "$cmd" == "chg" ] || [ "$cmd" == "del" ] || [ "$cmd" == "cfg" ]; then
	    suggestions=$(_wksps_completion_list "$cur")
	elif [ "$cmd" == "add" ]; then
	    suggestions=$(ls)
	elif [ "$cmd" == "ls" ]; then
	    if ! _wksps_args_is_option "$cur"; then
		suggestions=$(_wksps_wksp_ls_completion "$cur")
	    fi
	elif [ "$cmd" == "cd" ]; then
	    suggestions=$(_wksps_wksp_cd_completion "$cur")
	fi
    elif [ $COMP_CWORD -eq 3 ] && [ "$cmd" == "ls" ]; then
	suggestions=$(_wksps_wksp_ls_completion "$cur")
    fi
    COMPREPLY=( $(compgen -W "${suggestions}" -- ${cur}) )
    return 0
}
#export -f _wksps_wksp_autocomplete

#-------------------------------
# _wksps_ws_autocomplete () completion for ws command
#-------------------------------

_wksps_ws_autocomplete () {
    local suggestions
    local cur cmd

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [ $COMP_CWORD -eq 1 ]; then
	    suggestions=$(_wksps_completion_list "$cur")
    fi
    COMPREPLY=( $(compgen -W "${suggestions}" -- ${cur}) )
    return 0
}
#export -f _wksps_ws_autocomplete

#-------------------------------
# _wksps_wsls_autocomplete () completion for wsls command
#-------------------------------

_wksps_wsls_autocomplete () {
    local suggestions
    local cur cmd

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [ $COMP_CWORD -eq 1 ] && ! _wksps_args_is_option "$cur"; then
	suggestions=$(_wksps_wksp_ls_completion "$cur")
    fi
    COMPREPLY=( $(compgen -W "${suggestions}" -- ${cur}) )
    return 0
}
#export -f _wksps_wsls_autocomplete


#-------------------------------
# _wksps_wscd_autocomplete () completion for wscd command
#-------------------------------

_wksps_wscd_autocomplete () {
    local suggestions
    local cur cmd

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [ $COMP_CWORD -eq 1 ]; then
	suggestions=$(_wksps_wksp_cd_completion "$cur")
    fi
    COMPREPLY=( $(compgen -W "${suggestions}" -- ${cur}) )
    return 0
}
#export -f _wksps_wscd_autocomplete


#-----------------------------------------------------------------------
# User callable
#-----------------------------------------------------------------------

#------------------------------
# returns true (0) if any workspace is loaded and false (1) otherwise.
#------------------------------
wksps_is_loaded () {
    [ ! -z ${WORKSPACE_ID+"XXX"} ]
}

#-------------------------------
# Return true if the current shell is a workspace sub-shell
#-------------------------------
wksps_is_subshell () {
    if ! wksps_is_loaded ; then
	echo "error: call to wksps_is_subshell is only valid from a workspace shell"
	return 1
    fi

    # if WORKSPACE_BASH_ROOT_PID is not defined then it means that bash shell has been called
    # but the temporary initialisation file hasn't initialised WORKSPACE_BASH_ROOT_PID. This means
    # that it is a root shell.
    if [ -z ${WORKSPACE_BASH_ROOT_PID+XXX} ]; then
	return 1
    fi
    [ $WORKSPACE_BASH_ROOT_PID != $$ ]
}



#-------------------------------
# Returns the number of active pids in the current workspace
#-------------------------------

wksps_num_active_pids ()
{
    if [ "$WORKSPACE_DIR" == "" ] || ! _wksps_is_ws "$WORKSPACE_DIR" ; then
	echo "error: no active workspace"
    fi
    local npids=$(_wksps_num_active_pids "$WORKSPACE_DIR")
    echo $npids
}
#export -f wksps_num_active_pids

#-------------------------------
# wksps_hook_on_enter (<function name>) - register the function
# as a handler to be called before on_enter.sh is called for a
# workspace.
#-------------------------------

wksps_hook_on_enter ()
{
    local hookname="$1"
    if [ "$(declare -F $hookname)" == "" ]; then
	echo "error: invalid function callback: $hookname" 1>&2
	return 1
    fi
    WORKSPACES_HOOK_ON_ENTER[${#WORKSPACES_HOOK_ON_ENTER[@]}]=$hookname
}

#-------------------------------
# wksps_hook_on_exit (<function name>) - register the function
# as a handler to be called after on_exit.sh is called for a
# workspace.
#-------------------------------

wksps_hook_on_exit ()
{
    local hookname="$1"
    if [ "$(declare -F $hookname)" == "" ]; then
	echo "error: invalid function callback: $hookname" 1>&2
	return 1
    fi
    WORKSPACES_HOOK_ON_EXIT[${#WORKSPACES_HOOK_ON_EXIT[@]}]=$hookname
}


#-------------------------------
# wksp () [cw|push|pop] <arg>
#-------------------------------
wksp () {
    local cmd="$1"
    _wksps_init   # Make sure things are setup

    if [ "$cmd" == "chg" ]; then         # Change workspace
	_wksps_chgws $(_wksps_args 2 "$@")
    elif [ "$cmd" == "sel" ] || [ "$cmd" == "load" ]; then  # Select workspace from prompt
	_wksps_chgws_prompt
    elif [ "$cmd" == "add" ]; then       # Make workspace
	_wksps_mk_prompt $(_wksps_args 2 "$@")
    elif [ "$cmd" == "del" ]; then       # Remove workspaces
	_wksps_delws $(_wksps_args 2 "$@")
    elif [ "$cmd" == "list" ]; then       # List workspaces
	_wksps_listws $(_wksps_args 2 "$@")
    elif [ "$cmd" == "unload" ]; then  # Unload the current workspace
	_wksps_pop $(_wksps_args 2 "$@")
    elif [ "$cmd" == "reload" ]; then  # Reload the current workspace
	_wksps_reload $(_wksps_args 2 "$@")
    elif [ "$cmd" == "load_if" ]; then  # If curr dir is workspace then load it
	_wksps_load_if $(_wksps_args 2 "$@")
    elif [ "$cmd" == "cleanup" ]; then    # Makes sure all workspaces are valid
	_wksps_cleanup
    elif [ "$cmd" == "cfg" ]; then    # Configure the workspace
	_wksps_cfg $(_wksps_args 2 "$@")
    elif [ "$cmd" == "ls" ]; then    # Workspace relative ls
	_wksps_ls $(_wksps_args 2 "$@")
    elif [ "$cmd" == "cd" ]; then    # Workspace relative cd
	_wksps_cd $(_wksps_args 2 "$@")
    elif [ "$cmd" == "help" ]; then    # Show help information
	_wksps_help "wksp"
    else
	_wksps_help "wksp"
    fi

    return 0
}
#export -f wksp

#-------------------------------
# ws () Shortcut for wksp chg
#-------------------------------
ws () {
    _wksps_chgws "$@"
}
#export -f ws


#-------------------------------
# wsls () Shortcut for wksp ls
#-------------------------------
wsls () {
    _wksps_ls "$@"
}
#export -f wsls

#-------------------------------
# wscd () Shortcut for wksp cd
#-------------------------------
wscd () {
    _wksps_cd "$@"
}
#export -f wscd


#---------------------------------------------------------------
# Main - initialisation
#---------------------------------------------------------------

declare -a WORKSPACES_HOOK_ON_ENTER
declare -a WORKSPACES_HOOK_ON_EXIT


#---------------------------------------------------------------
# Register the completion functions
#---------------------------------------------------------------
complete -F _wksps_wksp_autocomplete wksp
complete -F _wksps_ws_autocomplete ws
complete -o nospace -F _wksps_wsls_autocomplete wsls
complete -o nospace -F _wksps_wscd_autocomplete wscd

