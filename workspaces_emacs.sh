#-------------------------------------------------------------------------
# workspaces_emacs.sh
#
# Functions to extend the workspaces stuff to make using emacs server 
# and client easier. The basic idea is that each workspace runs its own
# emacs server. When all instances of a workspace are shutdown the
# associated emacs server is also shutdown.
# 
# Connecting to a workspace's emacs server is simple using the "eedit"
# function. 
#
# Note on hackiness: I don't know how portable any of this is across 
# other platforms.
#
# Some issues:
# The emacsclient -a ""  doesn't seem to behave the way I would expect 
# a server name is specified. For example, I want to run a command like:
#
#    emacsclient -c -n -a "" -s myserver
# 
# What I would expect this to do is to try and connect to the emacs server
# daemon named "myserver" and if it is not running spawn a server with that
# name and connect to it. Instead, if the server is not running it spawns 
# a randomly named server and then fails to connect it because it has the
# wrong name.
#
# The wkspe_shutdown function needs work. It always prompts the user that
# there are "active clients". Searching google there are various discussions 
# on what this means and how to get around it. Need to look into it.
#
# wkspe_shutdown is best called from the workspace's on_exit.sh script.
#
#-------------------------------------------------------------------------


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
    local res=$(emacsclient -s "$WORKSPACE_ID" -e '(let ((nfrms (length (frame-list)))) (if (eq nfrms 1) (message "NO")))' 2>&1)
    [ "$res" == "" ]
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
    ! _wkspe_check_ws_loaded && return 0
    ! _wkspe_server_isrunning && return 0
    if _wkspe_has_frame; then
	emacsclient -s "$WORKSPACE_ID" -e '(save-buffers-kill-emacs)'
    elif [ "$DISPLAY" == "" ]; then
	emacsclient -t -s "$WORKSPACE_ID" -e '(save-buffers-kill-emacs)'
    else
	emacsclient -c -s "$WORKSPACE_ID" -e '(save-buffers-kill-emacs)'
    fi
}

#------------------------------
# My emacs edit command
#------------------------------
eedit(){
    ! _wkspe_check_ws_loaded && return 1
    ! _wkspe_server_isrunning && _wkspe_run_server
    if ! _wkspe_server_isrunning; then
	echo "error: failed to run emacs server"
	return 1
    fi
    if [ "$DISPLAY" == "" ]; then
	emacsclient -t -s "$WORKSPACE_ID" $@
    elif _wkspe_has_frame; then
	emacsclient -n -s "$WORKSPACE_ID" $@
    else
	emacsclient -c -n -s "$WORKSPACE_ID" $@
    fi
}


export -f _wkspe_check_ws_loaded
export -f _wkspe_run_server
export -f _wkspe_server_isrunning
export -f _wkspe_kill_server
export -f wkspe_shutdown
export -f eedit

