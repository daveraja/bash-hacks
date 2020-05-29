#-------------------------------------------------------------------------
# workspaces_emacs.sh
#
# Functions to extend the workspaces stuff to make using emacs server
# and client easier. The basic idea is that each workspace runs its own
# emacs server. When all instances of a workspace are shutdown the
# associated emacs server is also shutdown.
#
# workspaces_emacs registers itself with the workspaces on_exit hook so
# that the shutdown check is always checked on exiting a workspace.
#
# Note on hackiness: I don't know how portable any of this is across
# other platforms.
#
# Some issues:
# The emacsclient -a "" doesn't seem to behave the way I would expect
# when a server name is specified. For example, I want to run a
# command like:
#
#    emacsclient -c -n -a "" -s myserver
#
# What I would expect this to do is to try and connect to the emacs
# server daemon named "myserver" and if it is not running spawn a
# server with that name and connect to it. Instead, if the server is
# not running it spawns a randomly named server and then fails to
# connect to it because it has the wrong name.
#
# The wkspe_shutdown function needs work. It always prompts the user that
# there are "active clients". Searching google there are various discussions
# on what this means and how to get around it. Need to look into it.
#
#-------------------------------------------------------------------------
mbimport workspaces
mbimport prompts
mbimport logging

# name of emacs server when not in workspace
export GLOBAL_EMACS_SERVER_ID="${WORKSPACES_TMP_DIR}/eserver_global"

export WORKSPACE_EMACS_SERVER_ID=$(_wkspe_get_server_name)
#------------------------------
# validate_ws - If a workspace is loaded then do nothing, otherwise
# set the WORKSPACE_ID to a global value
#------------------------------
_wkspe_get_server_name(){
    if wksps_is_loaded ; then
	echo "${WORKSPACE_TMP_DIR}/eserver_${WORKSPACE_ID}"
    else
	echo "${WORKSPACES_TMP_DIR}/eserver_global"
    fi
    return 0
}

#------------------------------
# Check if the running emacs server has a frame (ie. a window or terminal in non-emacs speak).
# Note: for some reason the frame-list returns 1 if there are no frames not 0. Is this
# a bug or a property of the emacs server?
#------------------------------
_wkspe_has_frame(){
    local server_id=$(_wkspe_get_server_name)
    local res=$(emacsclient -s "$server_id" -e '(let ((nfrms (length (frame-list)))) (if (<= nfrms 1) (message "NO")))' 2>&1)
    if [[ "$res" =~ "NO" ]] ; then
	return 1
    fi
    return 0
}

#------------------------------
# Start up the emacs server for the workspace
#------------------------------
_wkspe_run_server(){
    local server_id=$(_wkspe_get_server_name)

#    echo "RUNNING $server_id"
    emacs --daemon="$server_id"
}

_wkspe_server_get_process(){
    local server_id=$(_wkspe_get_server_name)
    local match="daemon=$server_id"
    local res=$(pgrep -a emacs | grep "$match" | awk '{print $1}')
    echo "$res"
}

_wkspe_server_has_process(){
    local res=$(_wkspe_server_get_process)
    [ "$res" != "" ] && return 0
    return 1
}

_wkspe_server_has_socket(){
    local server_id=$(_wkspe_get_server_name)
    [ -S "$server_id" ] && return 0
    return 1
}

_wkspe_server_del_socket(){
    local server_id=$(_wkspe_get_server_name)
    if [ -S "$server_id" ] ; then
	rm -f "$server_id"
    fi
}

_wkspe_server_kill_process(){
    local res=$(_wkspe_server_get_process)
    [ "$res" == "" ] && return 0
    kill "$res"
    res=$(_wkspe_server_get_process)
    if [ "$res" != "" ] ; then
	log_error "Failed to delete emacs server process $res"
    fi
}

#------------------------------
# Check if the workspace emacs server is running
#------------------------------
_wkspe_server_isrunning(){
    local server_id=$(_wkspe_get_server_name)

    if _wkspe_server_has_process && _wkspe_server_has_socket ; then
	return 0
    fi
    if _wkspe_server_has_socket ; then
	log_error "Emacs server ($server_id) has a socket but no process"
	log_error "Deleting socket for server ($server_id)"
	_wkspe_server_del_socket
    fi
    if _wkspe_server_has_process ; then
	log_error "Emacs server ($server_id) has a process but no socket"
	log_error "Killing process for server ($server_id)"
	_wkspe_server_kill_process
    fi
    return 1
}

#------------------------------
# If a server is running then do return true (0).
# If in workspace and no server is running then run one.
# If not in workspace then prompt user.
# Returns the true (0) if a server is running.
#------------------------------
_wkspe_validate_running_server(){
    local server_id=$(_wkspe_get_server_name)
    _wkspe_server_isrunning && return 0
    local server_id=$(_wkspe_get_server_name)

    if [ "$server_id" == "$GLOBAL_EMACS_SERVER_ID" ] ; then
	local res=$(prompt_yesno "Not in workspace. Start global emacs server: \"$server_id\" (y/N)?" n)
	[ "$res" == "n" ] && return 1
    fi
    _wkspe_run_server
    _wkspe_server_isrunning && return 0

    log_error "Failed to run emacs server: \"$server_id\""
    return 1
}



#------------------------------
# Intelligently shutdown all emacs servers.
#------------------------------
#wkspe_shutdown_all(){
#    local servers=$(ps aux | grep "emacs --daemon="
#    local server_id=$(_wkspe_get_server_name)
#    ! _wkspe_server_isrunning && return 0

#    # Always exit in terminal mode
#    emacsclient -nw -s "$server_id" -e '(save-buffers-kill-emacs)'
#}

#------------------------------
# Intelligently shutdown the workspace emacs server (if it is running).
#------------------------------
wkspe_shutdown(){
    local server_id=$(_wkspe_get_server_name)
    local hasproc=$(_wkspe_server_has_process)
    local hassocket=$(_wkspe_server_has_socket)

    if _wkspe_server_has_process && _wkspe_server_has_socket ; then
	# Always exit in terminal mode
	emacsclient -nw -s "$server_id" -e '(save-buffers-kill-emacs)'
	return 0
    fi
    if _wkspe_server_has_process ; then
	_wkspe_server_kill_process
    fi
    if _wkspe_server_has_socket ; then
	_wkspe_server_del_socket
    fi

#    if _wkspe_has_frame; then
#	emacsclient -s "$server_id" -e '(save-buffers-kill-emacs)'
#    else
#	emacsclient -nw -s "$server_id" -e '(save-buffers-kill-emacs)'
#    fi
}

#------------------------------
# On exit of every workspace call this function.  If there are no more
# workspaces shells running then shutdown the workspace emacs server
# (if it is running).
#------------------------------
wkspe_on_exit(){
    # if no more active pids for the current workspace
    # then shutdown emacs server.
    local npids=$(wksps_num_active_pids)
    if [ $npids -eq 0 ] && _wkspe_server_isrunning ; then
	log_info "Shutting down emacs server for workspace..."
	wkspe_shutdown
    fi
}

#------------------------------
# On enter of every workspace call this function. Simply
# sets up the EDITOR variable.
#------------------------------
wkspe_on_enter(){
    local npids=$(wksps_num_active_pids)
    local server_id=$(_wkspe_get_server_name)

    # Check for a valid emacs server
    if _wkspe_server_isrunning ; then
	# If this was the first process then a previous server wasn't shutdown
	# properly. But still seems to be valid
	if [ $npids -eq 1 ]; then
	    log_warn "It appears that an Emacs server is already running for this workspace"
	fi
    fi
    export EDITOR=wkspe_emacsclient

}

#------------------------------
# My emacs edit command
#
#------------------------------
wkspe_emacsclient(){
    ! _wkspe_validate_running_server && return 1 # make sure emacs server is running
    local server_id=$(_wkspe_get_server_name)
    local nw=""
    if [ "$1" == "-nw" ] || [ "$1" == "-t" ] ; then
	nw="Yes"
	shift 1
    fi

    if [ "$DISPLAY" == "" ] || [ "$nw" != "" ] ; then
	emacsclient -nw -s "$server_id" $@
    elif _wkspe_has_frame ; then
	emacsclient -n -s "$server_id" $@
    else
	emacsclient -c -n -s "$server_id" $@
    fi
}

#------------------------------
# My emacs edit command that is terminal only
#------------------------------
wkspe_emacsclient_nw(){
    wkspe_emacsclient -nw $@
}

#------------------------------
# Emacs workspace - run ediff from the command-line
#------------------------------
wkspe_emacsclient_ediff(){
    local server_id=$(_wkspe_get_server_name)
    local nw=""
    if [ "$1" == "-nw" ] || [ "$1" == "-t" ] ; then
	nw="Yes"
	shift 1
    fi
    if [ "$1" == "" ] || [ "$2" == "" ] ; then
	echo "error: no files specified"
	return 1
    fi
    local cmd="(ediff-files \"$1\" \"$2\")"

    # make sure emacs server is running
    ! _wkspe_validate_running_server && return 1

    # Now run the ediff
    if [ "$DISPLAY" == "" ] || [ "$nw" != "" ] ; then
	emacsclient -nw -s "$server_id" -e "$cmd"
    elif _wkspe_has_frame ; then
	emacsclient -n -s "$server_id" -e "$cmd"
    else
	emacsclient -c -n -s "$server_id" -e "$cmd"
    fi
}

wkspe_emacsclient_ediff_nw(){
    wkspe_emacsclient_ediff -nw $@
}

_wkspe_emacsclient_ediff_autocomplete () {
    local suggestions
    local cur cmd

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [ $COMP_CWORD -eq 1 ] || [ $COMP_CWORD -eq 2 ] ; then
	suggestions=$(ls)
    fi
    COMPREPLY=( $(compgen -W "${suggestions}" -- ${cur}) )
    return 0
}

#-----------------------------------------------------------------------
# Main - Setup the workspace callback for on_enter and on_exit.
#-----------------------------------------------------------------------

wksps_hook_on_enter "wkspe_on_enter"
wksps_hook_on_exit "wkspe_on_exit"

#---------------------------------------------------------------
# Register the completion functions
#---------------------------------------------------------------
complete -F _wkspe_emacsclient_ediff_autocomplete wkspe_emacsclient_ediff
complete -F _wkspe_emacsclient_ediff_autocomplete wkspe_emacsclient_ediff_nw

export -f _wkspe_get_server_name
export -f _wkspe_has_frame
export -f _wkspe_run_server
export -f _wkspe_server_get_process
export -f _wkspe_server_has_process
export -f _wkspe_server_has_socket
export -f _wkspe_server_del_socket
export -f _wkspe_server_kill_process
export -f _wkspe_server_isrunning
export -f _wkspe_validate_running_server
export -f wkspe_shutdown
export -f wkspe_on_exit
export -f wkspe_on_enter
export -f wkspe_emacsclient
export -f wkspe_emacsclient_nw
export -f wkspe_emacsclient_ediff
export -f wkspe_emacsclient_ediff_nw
