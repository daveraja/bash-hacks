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

#------------------------------
# returns true if a workspace is loaded and false otherwise. If false
# writes out an error message.
#------------------------------
_wkspe_check_ws_loaded(){
    if [ "$WORKSPACE_ID" == "" ]; then
	echo "error: no workspace has been loaded"
	return 1
    fi
    return 0
}

#------------------------------
# Check if the running emacs server has a frame (ie. a window or terminal in non-emacs speak).
# Note: for some reason the frame-list returns 1 if there are no frames not 0. Is this
# a bug or a property of the emacs server?
#------------------------------
_wkspe_has_frame(){
    local res=$(emacsclient -s "$WORKSPACE_ID" -e '(let ((nfrms (length (frame-list)))) (if (<= nfrms 1) (message "NO")))' 2>&1)
    if [[ "$res" =~ "NO" ]]; then
	return 1
    fi
    return 0
}

#------------------------------
# Start up the emacs server for the workspace
#------------------------------
_wkspe_run_server(){
    emacs --daemon="$WORKSPACE_ID"
}

#------------------------------
# Check if the workspace emacs server is running
#------------------------------
_wkspe_server_isrunning(){
    local comm="emacs --daemon=$WORKSPACE_ID"
    local res=$(pgrep -f "$comm")
    [ "$res" != "" ]
}

#------------------------------
# NOTE: this kill server function is not currently being used.
#------------------------------
_wkspe_kill_server(){
    local comm="emacs --daemon=$WORKSPACE_ID"
    local res=$(pgrep -f "$comm")
    [ "$res" == "" ] && return 0
    kill $res
    res=$(pgrep -f "$comm")
    [ "$res" != "" ]
}

#------------------------------
# Intelligently shutdown the workspace emacs server (if it is running).
#------------------------------
wkspe_shutdown(){
    if [ "$WORKSPACE_ID" == "" ]; then
	echo "error: cannot shutdown emacs workspace server as no workspace is currently loaded"
	return 1
    fi
    ! _wkspe_server_isrunning && return 0
    if _wkspe_has_frame; then
	emacsclient -s "$WORKSPACE_ID" -e '(save-buffers-kill-emacs)'
    else
	emacsclient -nw -s "$WORKSPACE_ID" -e '(save-buffers-kill-emacs)'
    fi
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
	echo "Shutting down emacs server for workspace..."
	wkspe_shutdown
    fi
}

#------------------------------
# On enter of every workspace call this function. Simply
# sets up the EDITOR variable.
#------------------------------
wkspe_on_enter(){
    export EDITOR=wkspe_emacsclient
}

#------------------------------
# My emacs edit command
#
#------------------------------
wkspe_emacsclient(){
    if [ "$WORKSPACE_ID" == "" ]; then
	echo "error: cannot run emacs workspace server as no workspace is currently loaded"
	return 1
    fi
    ! _wkspe_server_isrunning && _wkspe_run_server
    if ! _wkspe_server_isrunning; then
	echo "error: failed to run emacs server"
	return 1
    fi
    local nw=""
    if [ "$1" == "-nw" ] || [ "$1" == "-t" ]; then
	nw="Yes"
	shift 1
    fi

    if [ "$DISPLAY" == "" ] || [ "$nw" != "" ] ; then
	emacsclient -nw -s "$WORKSPACE_ID" $@
    elif _wkspe_has_frame; then
	emacsclient -n -s "$WORKSPACE_ID" $@
    else
	emacsclient -c -n -s "$WORKSPACE_ID" $@
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
    if [ "$WORKSPACE_ID" == "" ]; then
	echo "error: cannot connect to emacs workspace server as no workspace is currently loaded"
	return 1
    fi

    local nw=""
    if [ "$1" == "-nw" ] || [ "$1" == "-t" ]; then
	nw="Yes"
	shift 1
    fi
    if [ "$1" == "" ] || [ "$2" == "" ]; then
	echo "error: no files specified"
	return 1
    fi
    local cmd="(ediff-files \"$1\" \"$2\")"

    # make sure emacs workspace server is running
    ! _wkspe_server_isrunning && _wkspe_run_server
    if ! _wkspe_server_isrunning; then
	echo "error: failed to run emacs server"
	return 1
    fi

    # Now run the ediff
    if [ "$DISPLAY" == "" ] || [ "$nw" != "" ]; then
	emacsclient -nw -s "$WORKSPACE_ID" -e "$cmd"
    elif _wkspe_has_frame; then
	emacsclient -n -s "$WORKSPACE_ID" -e "$cmd"
    else
	emacsclient -c -n -s "$WORKSPACE_ID" -e "$cmd"
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
    if [ $COMP_CWORD -eq 1 ] || [ $COMP_CWORD -eq 2 ]; then
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

export -f _wkspe_check_ws_loaded
export -f _wkspe_run_server
export -f _wkspe_server_isrunning
export -f _wkspe_kill_server
export -f _wkspe_has_frame
export -f wkspe_shutdown
export -f wkspe_emacsclient
export -f wkspe_emacsclient_nw
export -f wkspe_emacsclient_ediff
export -f wkspe_emacsclient_ediff_nw
