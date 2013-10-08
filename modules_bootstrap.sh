#----------------------------------------------------------------------
# modules_boostrap.sh
#
# Provides a simple module concept for bash. This allows for an easy way 
# to share code across many scripts by importing/loading modules. A module is 
# simply a bash file in a known location with a name ending in ".sh". 
# The module_boostrap provides basic functions to simplify loading the module.
# 
# Use case: 
# 
# 1) To reuse code in a shell script. For example, I have a bash function
#    that checks my laptop's IP address to work out if I am at home or 
#    in the office or on the road.  I want to use this function for 
#    different purposes, such as control what data is copied as part of 
#    a sync script and know whether or not to tunnel through SSH on a 
#    remote-desktop script.
#
# 2) I don't really want to polute my 'bin' directory with lots of support
#    files so need to put these files in a different directory. But then
#    I don't want to have to specify the path names in all my scripts.
#
# 3) Want to allow modules to depend on other modules. So need to make 
#    sure that we only load a module once and don't get stuck in 
#    circular dependencies.
# 
# Usage:
#     mbimport <module_name> [module_arguments]
#
#     mbforce <module_name> [module_arguments]
#     
# A module name is restricted to the characters allowed for a bash
# function or variable name. So stick to [a-zA-Z0-9_-] characters.
#
# Environment variables:
#
# MODULE_PATH - a ':' separated list of paths to check for the location
#               of a module. Paths are checked sequentially until a
#               match is found or it fails, so only the first module
#               with the name will be loaded.
#
# _MB_IMPORTED_<module_name> - This will be set to 1 when the module
#              is loaded. Should never be set manually, but might be
#              be useful for testing. In particularly, useful for
#              testing if this script "boostrap_modules" has itself
#              already been loaded. For example at the start of your
#              bashrc you could add:
#
#  [ "$_MB_IMPORTED_bootstrap_modules" != "1" ] && . ~/.bash.d/bootstrap_modules
#
# TO DO: Be smart about exporting environment variables and functions.
#
#-------------------------------------------------------------------------
# Issue - the question of exports
# -------------------------------
# There may be times when you want variables and functions to be exported
# to the environment so that it will be inherited by child processes and
# sub-shells. But there may also be times when you don't want/need this.
#
# The question is, is it possible to re-use the same module for both cases?
# If not the alternative is that it is up to the module itself to export 
# variables and functions. I guess could adopt a convention of having
# a base module with no exports and then having a export version module 
# which simply imports the base and adds some export statements. 
# 
# Toying with having an environment variable to control this behaviour.
# The module loader will then pseudo-magically generate "export <varname>" 
# and "export -f <funcname>" statements if necessary. 
# 
# Not sure if this can be made to work nicely or if it would be too brittle.
# 
# MODULE_NOEXPORT - By default both variables and functions in a module are
#                exported, so inherited by sub-shells. If this environment 
#                variable is set to a value other than 0 then the module
#                variables and functions will not be exported (unless the
#                module explicitly exports them itself).
#
#----------------------------------------------------------------------


#----------------------------------------------------------------------
# Internal functions - Shouldn't call these externally.
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# Get the module variable name used to indicate if the module has
# been loaded.
#----------------------------------------------------------------------
_modules_get_module_varname (){
   echo "_MB_IMPORTED_$1"
 }

#----------------------------------------------------------------------
# Checks if a module has been loaded
#----------------------------------------------------------------------
_modules_is_module_loaded (){
    local varname=$(_modules_get_module_varname "$1")
    eval var=\$$varname
    if [ "$var" == "1" ]; then return 0; fi
    return 1
}

#----------------------------------------------------------------------
# Get module specific arguments by removing the first argument
#----------------------------------------------------------------------
_modules_get_module_arguments (){
    local prt=0
    for opt in "$@"; do
	if [ $prt -eq 0 ]; then 
	    prt=1
	else
	    echo $opt
	fi
    done
}

#----------------------------------------------------------------------
# returns a directory name with no ending /
#----------------------------------------------------------------------
_modules_clean_dirname (){
    echo $( echo "$1" | sed -e 's!^\(.*\)/$!\1!')
}

#----------------------------------------------------------------------
# Find the file (by searching the MODULE_PATH) that corresponds to
# the module with the given name
#----------------------------------------------------------------------
_modules_get_filename_from_modulename (){
    local modulename="$1"
    local modfilename=""
    for pth in $(echo $MODULE_PATH | tr ":" "\n"); do
	modfilename="$(_modules_clean_dirname $pth)/$modulename.sh"
	[ -f $modfilename ] && break
    done
    echo "$modfilename"
}

#----------------------------------------------------------------------
# returns the modulename from a filename
#----------------------------------------------------------------------
_modules_get_modulename_from_filename (){
    echo $( basename "$1" | sed -n 's/^\(.*\)\.sh$/\1/p')
}

#----------------------------------------------------------------------
# Set the default MODULE_PATH to include the location of this file
#----------------------------------------------------------------------
_modules_set_MODULE_PATH (){
    local tf="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    if [ "$MODULE_PATH" != "" ]; then
	for pth in $(echo $MODULE_PATH | tr ":" "\n"); do
	    local toadd=$( _modules_clean_dirname "$pth" )
	    if [ "$toadd" == "$tf" ]; then
		return 0
	    fi
	done
	MODULE_PATH="$MODULE_PATH":"$tf"
    else
	MODULE_PATH="$tf"
    fi    
}

#----------------------------------------------------------------------
# See here for ways to list variables:
# http://stackoverflow.com/questions/1305237/how-to-list-variables-declared-in-script-in-bash
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# TEST CODE - generate export statements for variables and functions.
#----------------------------------------------------------------------
_modules_varfuncs(){
    # Save the variable and function declarations
    declare -A prevar; declare -A prefunc
    for n in $(compgen -v); do prevar[$n]=1; done
    for n in $(declare -F | sed -n 's/^declare\s\+.\+\s\+\(.*\)$/\1/p'); do 
	prefunc[$n]=1
    done


    # Check if we need to export the variables and functions
    if [ "$MODULE_NOEXPORT" != "" ] && [ "$MODULE_NOEXPORT" != "0" ]; then return 0; fi
    for n in $(compgen -v);  do
	echo "REPRA: $n=" ${prevar[$n]}
	[ "${prevar[$n]}" != "" ] && [ ${prevar[$n]} -eq 1 ] && continue
	echo "NEWVAR: $n"
	eval "export $n"
    done
    return 0
    for n in $(declare -F | sed -n 's/^declare\s\+.\+\s\+\(.*\)$/\1/p');  do
	local res=$prevar[$n]
	[ "$res" != "" ] && [ $res -eq 1 ] && continue
	echo "NEWFUNC: $n"
	eval "export -f $n"
    done

}


#----------------------------------------------------------------------
# Externally callable functions
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# Load a "module" regardless of whether it has been loaded in the past
#----------------------------------------------------------------------
mbforce() {
    local modulename="$1"
    local modfilename=$(_modules_get_filename_from_modulename "$modulename")
    if [ "$modfilename" == "" ]; then
	echo "error: cannot find module $modulename" 1>&2
	return 1
    fi
    local args=$(_modules_get_module_arguments "$@")

    # Load up the module
    source $modfilename "$args" 
    if [ $? -eq 1 ]; then
	echo "error: failed to load: $modfilename" 1>&2
	return 1
    fi
    local imported=$(_modules_get_module_varname "$modulename")
    local toeval="$imported=1"
    eval $(echo $toeval)
    return 0
}

#----------------------------------------------------------------------
# Import a "module" if it hasn't already been loaded
#----------------------------------------------------------------------
mbimport() {
    if _modules_is_module_loaded "$1"; then return 0; fi
    if mbforce "$@"; then return 0; else return 1; fi
}


#----------------------------------------------------------------------
# Main 
#----------------------------------------------------------------------

_modules_set_MODULE_PATH
if [ "$MODULE_NOEXPORT" != "" ] || [ "$MODULE_NOEXPORT" == "0" ]; then
    export -f _modules_get_module_varname
    export -f _modules_is_module_loaded
    export -f _modules_get_module_arguments
    export -f _modules_get_filename_from_modulename
    export -f _modules_set_MODULE_PATH
    export -f module_force
    export -f module_import
    eval "export _MB_IMPORTED_$(_modules_get_modulename_from_filename ${BASH_SOURCE[0]})=1"
    export MODULE_PATH
else
    eval "_MB_IMPORTED_$(_modules_get_modulename_from_filename ${BASH_SOURCE[0]})=1"
fi
