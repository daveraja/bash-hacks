#-------------------------------------------------------------------------
# workspaces_ros.sh
#
# Functions to extend the bash workspaces module to add features for working
# with ROS (Robot Operating System) and the ROS catkin workspaces.
#
# The basic idea is to allow the bash workspace to contain multiple catkin
# workspaces. For the first instance of the bash workspace it prompts you to
# select a catkin workspace. For subsequent instances it uses the same catkin
# workspace.
#
# Creates a temporary file with in the workspace directory:
#      ./.worspace/ros_default.tmp
#
# This stores the default ROS catkin workspace to load for subsequent instances.
#
# Environment variables used:
# - WKSPR_ROS_INSTALL_DIR - Can be used to overide the computed ROS install
#                           directory (which is "/opt/ros/${ROS_VERSION}").
# - WKSPR_ROOT_DIR - The root directory containing the various catkin workspaces
# - WKSPR_DEFAULT_ROOT_DIR - A default for the root directory containing
#                            the various catkin workspaces.
# - WKSPR_ACTIVE_CATKIN_WKSP_FILE - The name of the file containing the active
#                                   catkin workspace.
# - WKSPR_ACTIVE_CATKIN_WKSP - The active catkin workspace
#
# -------------------------------------------------------------------------

mbimport workspaces
mbimport prompts

#-----------------------------------------
# _wkspr_(un)setenv - set and unset default environment variables
#-----------------------------------------
_wkspr_setenv(){
    export WKSPR_ACTIVE_CATKIN_WKSP_FILE=${WORKSPACE_TMP_DIR}/ros.sh.tmp
    export WKSPR_DEFAULT_ROOT_DIR=${WORKSPACE_DIR}/ros_wksps
}

_wkspr_unsetenv(){
    unset WKSPR_ACTIVE_CATKIN_WKSP_FILE
    unset WKSPR_DEFAULT_ROOT_DIR
}

#-----------------------------------------
# _wkspr_init - initialise the system. Sets the root dir (if not already set)
# and create this root directory if doesn't already exist.
#-----------------------------------------
_wkspr_init(){
    if [ -z ${WKSPR_ROOT_DIR+XXX} ] || [ "${WKSPR_ROOT_DIR}" == "" ] ; then
	export WKSPR_ROOT_DIR=${WKSPR_DEFAULT_ROOT_DIR}
    fi
    if [ -d ${WKSPR_ROOT_DIR} ]; then
	return 0
    fi
    echo "Creating ROS root directory: ${WKSPR_ROOT_DIR}"
    mkdir -p ${WKSPR_ROOT_DIR}
}

#-----------------------------------------
# _wkspr_load_catkin_ws <catkis_ws> - Load the given catkin workspace (where the
# workspace is relative to the workspace_root_dir.
#-----------------------------------------
_wkspr_load_catkin_ws(){
    local ros_wksp="$1"
    local ros_wksp_dir="${WKSPR_ROOT_DIR}/${ros_wksp}"
    local ros_install_dir="${WKSPR_ROS_INSTALL_DIR}"
    local ros_local="${ros_wksp_dir}/devel/setup.bash"
    if [ "$ros_install_dir" == "" ]; then
	ros_install_dir="/opt/ros/${ROS_VERSION}"
    fi
    local ros_install="$ros_install_dir/setup.bash"

    if [ -f $ros_local ]; then
	echo "Sourcing ${ros_local}"
	source $ros_local
	cd "${ros_wksp_dir}"
    else
	echo "Catkin workspace '$ros_wksp' is not setup"
	echo "Sourcing the ROS installation: $ros_install"
	source $ros_install
    fi
}

#-----------------------------------------
# _wkspr_remove_active_catkin_ws
#-----------------------------------------
_wkspr_remove_active_catkin_ws(){
    [ -z ${WKSPR_ACTIVE_CATKIN_WKSP_FILE+XXX} ] && return 1
    if [ -f ${WKSPR_ACTIVE_CATKIN_WKSP_FILE} ]; then
	rm -f ${WKSPR_ACTIVE_CATKIN_WKSP_FILE}
    fi
}

#-----------------------------------------
# wkspr_prompt_catkin_ws - Prompt for a catkin workspace
#-----------------------------------------
_wkspr_prompt_catkin_ws(){
    local count=$(find -L "${WKSPR_ROOT_DIR}" -maxdepth 1 -type d -printf '%f\n' | wc -l)
    count=$(($count-1))
    if [ $count == 0 ]; then
	echo "No catkin workspaces in ${WKSPR_ROOT_DIR}"
	return 1
    fi
    local wksps=$(find -L "${WKSPR_ROOT_DIR}"/* -maxdepth 0 -type d -printf '%f\n' | xargs echo)
    local wksps="$wksps <None>"
    local ros_wksp=$(prompt_choose ${wksps})

    if [ "$ros_wksp" != "<None>" ]; then
	echo "export WKSPR_ACTIVE_CATKIN_WKSP=$ros_wksp" > "${WKSPR_ACTIVE_CATKIN_WKSP_FILE}"
	_wkspr_load_catkin_ws "$ros_wksp"
	return 0
    fi
    _wkspr_remove_active_catkin_ws
    return 1
}

#-----------------------------------------
# wkspr - Select the active catkin workspace. Will prompt unless the argument "use-default" is given.
#-----------------------------------------
wkspr_select(){
    local option="$1"
    _wkspr_init # Make sure things are setup

    # If we don't need to prompt then just load it
    if [ "$option" == "use-default" ] && [ -f ${WKSPR_ACTIVE_CATKIN_WKSP_FILE} ] ; then
	source ${WKSPR_ACTIVE_CATKIN_WKSP_FILE}
	if [ -z ${WKSPR_ACTIVE_CATKIN_WKSP+XXX} ]; then
	    echo "Error in ${WKSPR_ACTIVE_CATKIN_WKSP_FILE}. It doesn't define WKSPR_ACTIVE_CATKIN_WKSP"
	    return 1
	fi
	_wkspr_load_catkin_ws ${WKSPR_ACTIVE_CATKIN_WKSP}
    else
	_wkspr_prompt_catkin_ws
    fi
}




#-----------------------------------------
# on_enter and on_exit
#-----------------------------------------
wkspr_on_enter(){
    _wkspr_setenv
}

wkspr_on_exit(){
    _wkspr_setenv
    local npids=$(wksps_num_active_pids)
    if [ $npids -eq 0 ] ; then
	_wkspr_remove_active_catkin_ws
    fi
    _wkspr_unsetenv
}


#-----------------------------------------------------------------------
# Main - Setup the workspace callback for on_enter and on_exit.
#-----------------------------------------------------------------------

wksps_hook_on_enter "wkspr_on_enter"
wksps_hook_on_exit "wkspr_on_exit"

#---------------------------------------------------------------
# Register the completion functions
#---------------------------------------------------------------

export -f _wkspr_init
export -f _wkspr_load_catkin_ws
export -f _wkspr_remove_active_catkin_ws
export -f _wkspr_prompt_catkin_ws
export -f wkspr_select
export -f wkspr_on_enter
export -f wkspr_on_exit


