#--------------------------------------------------------------------
#
# Functions to help with using conda
# -
#--------------------------------------------------------------------

mbimport logging
mbimport misc_functions

#--------------------------------------------------------------------
# Check if the conda command is present
#--------------------------------------------------------------------
conda_has_cmdline(){

    # A shell function
    if [ "$(type -t conda)" == "function" ]; then
	return 0
    fi
    if [ "$(mf_which conda)" != "" ]; then
	return 0
    fi
    return 1
}

#----------------------------------------------------------------------------
# Because shell function are typically not exported (ie. need "export -f ...")
# which means that conda environments cannot be activated from a shell
# script. Fortunately conda typically adds to the PATH where there is a "conda"
# script. This script can then be used to bootstrap the shell to load all the
# bash conda function.
# ---------------------------------------------------------------------------
conda_setup_shell(){
    if ! conda_has_cmdline; then
	log_error "Conda is not setup, so cannot source profile"
	return 0
    fi
    eval "$(conda shell.bash hook)"
#    local base=$(conda info --base)
#    source ${base}/profile/
}

#--------------------------------------------------------------------
# conda_list_envs
#--------------------------------------------------------------------
conda_list_envs(){
    if ! conda_has_cmdline; then
	log_warn "Conda is not setup, so there are no environments"
	return 0
    fi
    local out=$(conda info --envs | sed '/^\s*$/d' | sed '/^#/d' | sed '/^base/d' | sed -r 's/\S+//2')
    echo "$out"
    return 0
}

#--------------------------------------------------------------------
# conda_env_exists - check if an environment exists
#--------------------------------------------------------------------
conda_env_exists(){
    local env="$1"
    local filter=$(conda_list_envs | sed -n 's/^\s*\('$env'\)\s*$/\1/p')
    if [ "$filter" != "$env" ]; then
	return 1
    fi
    return 0
}

#--------------------------------------------------------------------
# conda_activate - a wrapper around conda activate
#--------------------------------------------------------------------
conda_activate(){
    local env="$1"
    if conda_env_exists $env ; then
	conda activate $env
    elif conda_has_cmdline; then
	local tmp1=$(conda_list_envs | sed 'N;s/\s*\n/, /')
	log_error "Conda environment $env does not exist."
	log_error "Valid environments: $tmp1"
    else
	log_error "Conda is not setup"
    fi
}

#--------------------------------------------------------------------
# conda_deactivate
#--------------------------------------------------------------------
conda_deactivate(){
    conda deactivate
}


