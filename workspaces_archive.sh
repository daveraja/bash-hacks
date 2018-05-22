#-------------------------------------------------------------------------
# workspaces_archive.sh
#
# Functions to support the archiving of workspaces.
#
# Environment variables to override default module behaviour:
#
# - WORKSPACES_ARCHIVE_BASE_DIR - Base directory for the squashfs archives and metadata.
#                                 By default use: ~/Documents/Archive
#
# Environment variables used internally by module:
#
# - _WKSPSA_SFS_DIR - location of the squashFS files. Each file must be
#                     of the form <workspace-id>.sqfs
# - _WKSPSA_MD_DIR - meta-data file for each workspace. Contains location
#                    for mounting the squashfs filesystem.
# - _WKSPSA_SQFS_MAKE_CMD -
# - _WKSPSA_SQFS_EXTRACT_CMD -
# - _WKSPSA_SQFS_MOUNT_CMD -
# - _WKSPSA_SQFS_UNMOUNT_CMD -
# - _WKSPSA_SQFS_ENABLED
# -------------------------------------------------------------------------
mbimport workspaces
mbimport logging
mbimport prompts
mbimport misc_functions

#--------------------------------------------------------------------------
# Check that the external SQUASHFS dependencies are satisfied and setup
# the approapriate executables.
#--------------------------------------------------------------------------

_squashfs_fusermount_cmd(){
    echo $(mf_which fusermount)
}
_squashfs_make_cmd(){
    echo $(mf_which mksquashfs)
}
_squashfs_extract_cmd(){
    echo $(mf_which unsquashfs)
}
_squashfs_mount_cmd(){
    echo $(mf_which squashfuse)
}
_squashfs_unmount_cmd(){
    local fusermount=$(_squashfs_fusermount_cmd)
    if [ "$fusermount" = "" ]; then
	log_error "Could not find fusermount command"
	echo ""
	return 1
    fi
    echo "$fusermount -u"
}

_WKSPSA_SQFS_MAKE_CMD=$(_squashfs_make_cmd)
_WKSPSA_SQFS_EXTRACT_CMD=$(_squashfs_extract_cmd)
_WKSPSA_SQFS_MOUNT_CMD=$(_squashfs_mount_cmd)
_WKSPSA_SQFS_UNMOUNT_CMD=$(_squashfs_unmount_cmd)

_wkspsa_sqfs_enabled(){
    local error=0
    if [ "$_WKSPSA_SQFS_MAKE_CMD" == "" ] || \
       [ "$_WKSPSA_SQFS_EXTRACT_CMD" == "" ]; then
	log_error "SQUASHFS is not installed"
	error=1
    fi
    if [ "$_WKSPSA_SQFS_MOUNT_CMD" == "" ] || \
       [ "$_WKSPSA_SQFS_UNMOUNT_CMD" == "" ]; then
	log_error "SQUASHFUSE is not installed"
	error=1
    fi
    return $error
}
_WKSPSA_SQFS_ENABLED=$(_wkspsa_sqfs_enabled)


# -------------------------------------------------------------------------
# constants
# Checks whether WORKSPACES_ARCHIVE_BASE_DIR is set and if not sets it to
# $HOME/Documents/Archive
# -------------------------------------------------------------------------

_wkspsa_set_env (){
    if [ "$WORKSPACES_ARCHIVE_BASE_DIR" == "" ]; then
	export WORKSPACES_ARCHIVE_BASE_DIR="$HOME/Documents/Archive"
    fi
    export _WKSPSA_SFS_DIR=$WORKSPACES_ARCHIVE_BASE_DIR/sqfs
    export _WKSPSA_MD_DIR=$WORKSPACES_ARCHIVE_BASE_DIR/metadata
}

_wkspsa_init (){
    if [ ! -d "$WORKSPACES_ARCHIVE_BASE_DIR" ]; then
	log_info "Creating workspaces archive base directory: $WORKSPACES_ARCHIVE_BASE_DIR"
	mkdir -p "$WORKSPACES_ARCHIVE_BASE_DIR"
	mkdir -p "$_WKSPSA_SFS_DIR"
	mkdir -p "$_WKSPSA_MD_DIR"
    fi
    if [ ! -d "$_WKSPSA_SFS_DIR" ]; then
	log_info "Creating workspaces archive squashfs directory: $_WKSPSA_SFS_DIR"
	mkdir -p "$_WKSPSA_SFS_DIR"
    fi
    if [ ! -d "$_WKSPSA_ME_DIR" ]; then
	log_info "Creating workspaces archive metadata directory: $_WKSPSA_MD_DIR"
	mkdir -p "$_WKSPSA_MD_DIR"
    fi
}

#--------------------------------------------------------------------------
# Make an archive file
# squashfs_make <directory> <archive-file>
#--------------------------------------------------------------------------

_wkspsa_sqfs_make (){
    local dir_to_archive="$1"
    local archive_name="$2"
    local res=$(prompt_yesno "Run '$SQUASHFS_MAKE_CMD $dir_to_archive $archive_name' ?" y)
    if [ "$res" == "n" ]; then
	return 0
    fi
    local output=$($_WKSPSA_SQFS_MAKE_CMD "$dir_to_archive" "$archive_name" 2>&1)
    res=$?
    if (($res > 0)) ; then
	log_error "Make squashfs failed: $output"
	return 1
    fi
    return 0
}


# -------------------------------------------------------------------------
# wkspsa_is_archived <workspace-id>
# -------------------------------------------------------------------------

_wkspsa_is_archive(){
    local wsid="$*"
    local sqfsfn="$_WKSPSA_SFS_DIR/$wsid.sqfs"
    local metadatafn="$_WKSPSA_MD_DIR/$wsid.md"

    if [ -f "$sqfsfn" ] || [ -f "$metadatafn" ]; then
	return 0
    fi
    return 1
}

# -------------------------------------------------------------------------
# Make an archived workspace
# wkspsa_make <workspace-id>
# -------------------------------------------------------------------------

_wkspsa_make(){
    local wsid="$*"
    local wsdir=$(_wksps_get_ws_from_link_id "$wsid")
    if [ "$wsdir" == "" ]; then
	log_error "Not a workspace, cannot archive: $wsdir"
	return 1
    fi
    if _wkspsa_is_archive "$wsid" ; then
	log_error "Workspace is already an archive: $wsid"
	return 1
    fi
    if _wksps_is_active "$wsdir"; then
	log_error "Cannot archive an active workspace"
	return 1
    fi

    local res=$(prompt_yesno "Are you sure you want to archive the workspace $wsdir (y/N)" n)
    [ "$res" == "n" ] && return 0

    log_info ""
    log_info "Archiving workspace $absws with ID $wsid"
    wsdesc=$(prompt_input "Enter a workspace description (optional): ")

    local sqfsfn="$_WKSPSA_SFS_DIR/$wsid.sqfs"
    local metadatafn="$_WKSPSA_MD_DIR/$wsid.md"

    echo "WORKSPACE_ID=$wsid" > $metadatafn
    echo "WORKSPACE_DIR=$wsdir" >> $metadatafn
    echo "WORKSPACE_DESCRIPTION=\"$wsdesc\"" >> $metadatafn

    log_info ""
    log_warn "Creating archive file $wsdir"
    if ! _wkspsa_sqfs_make "$wsdir" "$sqfsfn"; then
	rm -f $metadatafn
	return 1
    fi
    log_info "Archive file created: $sqfsfn"
    log_info ""
    log_warn "Removing workspace directory: $wsdir"

    _wksps_remove_ws_link $wsdir
    prompt_run rm -rf $wsdir
}

# -------------------------------------------------------------------------
# Restore the archive back to its original form
# wkspsa_mount <workspace-id>
# -------------------------------------------------------------------------

_wkspsa_restore(){
    local wsid="$*"
    local sqfsfn="$_WKSPSA_SFS_DIR/$wsid.sqfs"
    local metadatafn="$_WKSPSA_MD_DIR/$wsid.md"
    if ! _wkspsa_is_archive "$wsid" ; then
	log_error "There is no archived workspace: $wsid"
	return 1
    fi
    local wsdir=$(_wksps_get_ws_from_link_id "$wsid")
    if [ "$wsdir" != "" ]; then
	log_error "There is already an active workspace with id $wsid: $wsdir"
	return 1
    fi
    wsdir=$(grep WORKSPACE_DIR $metadatafn | sed 's/WORKSPACE_DIR=//')

    # Create the directory, extraxt the archive and restore the link
    #    mkdir -p $wsdir
    $_WKSPSA_SQFS_EXTRACT_CMD -d $wsdir $sqfsfn
    _wksps_create_ws_link $wsdir
    rm -f $sqfsfn
    rm -f $metadatafn

    return 0
}

# -------------------------------------------------------------------------
# Mount an archived workspace
# wkspsa_mount <workspace-id>
# -------------------------------------------------------------------------

_wkspsa_mount(){
    local wsid="$*"
    local wsdir
    local sqfsfn="$_WKSPSA_SFS_DIR/$wsid.sqfs"
    local metadatafn="$_WKSPSA_MD_DIR/$wsid.md"
    if ! _wkspsa_is_archive "$wsid" ; then
	log_error "There is no archived workspace: $wsid"
	return 1
    fi
    if _wksps_has_ws_link_id "$wsid"; then
	wsdir=$(_wksps_get_ws_from_link_id )
	log_error "There is already an active workspace with id $wsid: $wsdir"
	return 1
    fi

    wsdir=$(grep WORKSPACE_DIR $metadatafn | sed 's/WORKSPACE_DIR=//')

    # Create a mount point, mount the archive file and setup the workspace link
    log_info "Mounting $wsid to $wsdir"
    mkdir -p $wsdir
    $_WKSPSA_SQFS_MOUNT_CMD $sqfsfn $wsdir
    _wksps_create_ws_link $wsdir

    return 0
}

# -------------------------------------------------------------------------
# Unount an archived workspace
# wkspsa_mount <workspace-id>
# -------------------------------------------------------------------------
_wkspsa_unmount(){
    local wsid="$*"
    if ! _wkspsa_is_archive "$wsid" ; then
	log_error "There is no archived workspace: $wsid"
	return 1
    fi
    local wsdir=$(_wksps_get_ws_from_link_id "$wsid")
    if _wksps_is_active "$wsdir"; then
	log_error "The archived workspace is current active: $wsdir"
	return 1
    fi
    $_WKSPSA_SQFS_UNMOUNT_CMD $wsdir
    local res=$?
    if (($res > 0)) ; then
	log_error "Failed to unmount $wsdir"
	return $res
    fi
    # Remove the workspace symlink. Unmount and delete the mount point
    _wksps_remove_ws_link_id $wsid
    rmdir $wsdir
    return 0
}

#---------------------------------
# Setup a global array of archived workspaces
#---------------------------------
declare -a _WKSPSA_ARCHIVES_ID
declare -a _WKSPSA_ARCHIVES_DIR
declare -a _WKSPSA_ARCHIVES_DESC

#---------------------------------
# wkspsa_ls ([mounted|inactive|active|all])
# Show help information:
# - mounted: mounted (irrespective of if the workspace has active shells)
# - inactive: mounted but no current shells open.
# - active: mounted and has current shells open.
# - all: all archives
#---------------------------------
_wkspsa_filtered_ls () {
    local option="$*"
    local wsid
    local wsdir
    local wsdesc
    local isok
    local isws
    local isactws

    if [ "$option" != "" ] && [ "$option" != "all" ] && \
       [ "$option" != "unmounted" ] && [ "$option" != "mounted" ] && \
       [ "$option" != "inactive" ] && [ "$option" != "active" ]; then
	log_error "Invalid option for viewing workspaces: $option"
	return 1
    fi
    _WKSPSA_ARCHIVES_ID=()
    _WKSPSA_ARCHIVES_DIR=()
    _WKSPSA_ARCHIVES_DESC=()
    for fn in "$_WKSPSA_MD_DIR/"*.md; do
	[ -f "$fn" ] || continue
	wsid=$(grep WORKSPACE_ID $fn | sed 's/WORKSPACE_ID=//')
	wsdir=$(grep WORKSPACE_DIR $fn | sed 's/WORKSPACE_DIR=//')
	wsdesc=$(grep WORKSPACE_DESCRIPTION $fn | sed 's/WORKSPACE_DESCRIPTION=//' | sed 's/^"//'  | sed 's/"$//')
	isws="no"
	isactws="no"
	_wksps_is_ws "$wsdir" && isws="yes"
	_wksps_is_active "$wsdir" && isactws="yes"

	isok="no"
	if [ "$option" == "" ] || [ "$option" == "all" ] ; then
	    isok="yes"
	elif [ "$option" == "unmounted" ] && [ "$isws" != "yes" ]; then
	    isok="yes"
	elif [ "$isws" == "yes" ]; then
	    if [ "$option" == "mounted" ]; then
		isok="yes"
	    elif [ "$option" == "inactive" ] && [ "$isactws" != "yes" ]; then
		isok="yes"
	    elif [ "$option" == "active" ] && [ "$isactws" == "yes" ]; then
		isok="yes"
	    fi
	fi
	if [ "$isok" == "yes" ] ; then
	    _WKSPSA_ARCHIVES_ID+=("$wsid")
	    _WKSPSA_ARCHIVES_DIR+=("$wsdir")
	    _WKSPSA_ARCHIVES_DESC+=("$wsdesc")
	fi
    done
}

_wkspsa_ls (){
    _wkspsa_filtered_ls "all"
    for i in "${!_WKSPSA_ARCHIVES_ID[@]}"; do
	echo "${_WKSPSA_ARCHIVES_DIR[$i]} | ${_WKSPSA_ARCHIVES_ID[$i]} | ${_WKSPSA_ARCHIVES_DESC[$i]}"
    done
}


#---------------------------------
# wkspsa_sel_archive ()
# Selects an archive - must call _wkspsa_filtered_ls first
#---------------------------------
_wkspsa_sel_archive ()
{
    local prompt="$@"
    local tmpi
    local res=""
    local answr

    if [ "${#_WKSPSA_ARCHIVES_ID}" -eq 0 ]; then
	echo ""
	return 0
    fi

    # Display the sorted list with a number for each selection
    for i in "${!_WKSPSA_ARCHIVES_ID[@]}"; do
	tmpi=$(($i + 1))
	log_info "$tmpi) ${_WKSPSA_ARCHIVES_DIR[$i]} | ${_WKSPSA_ARCHIVES_ID[$i]} | ${_WKSPSA_ARCHIVES_DESC[$i]}"
    done

    # Read/validate/return the answer
    while [ "$res" == "" ]; do
	read -p "$prompt" answr
	if ! mf_is_number $answr; then
	    log_error "not a number: $answr" 1>&2
	elif [ "$answr" -gt "0" ] && [ $answr -le ${#_WKSPSA_ARCHIVES_ID[@]} ]; then
	    tmpi=$(( $answr - 1 ))
	    res="${_WKSPSA_ARCHIVES_ID[$tmpi]}"
	else
	    log_error "out of range selection: $answr" 1>&2
	fi
    done
    echo "$res"
}

_wkspsa_mount_sel (){
    _wkspsa_filtered_ls "unmounted"
    local wsid=$(_wkspsa_sel_archive "Select archive to mount: ")
    if [ "$wsid" == "" ]; then
	log_error "No available archives to mount"
    else
	_wkspsa_mount $wsid
    fi
}

_wkspsa_unmount_sel (){
    _wkspsa_filtered_ls "inactive"
    local wsid=$(_wkspsa_sel_archive "Select archive to unmount: ")
    if [ "$wsid" == "" ]; then
	log_error "No available archives to unmount"
    else
	_wkspsa_unmount $wsid
    fi
}


#---------------------------------
# wkspsa_help ()
# Show help information
#---------------------------------
_wkspsa_help () {
    echo "Usage: $1 <COMMAND>"
    echo
    echo "Available commands:"
    echo "list             List available archived workspaces."
    echo "archive          Archive an existing workspace."
    echo "mount            Mount a read-only view of an archive."
    echo "unmount          Unmount an archive".
    echo "help             this help information."
}


#---------------x2------------------
# Has mounted archived
# returns 0 (true) if there is a mounted archive and 1 (false) otherwise
#---------------------------------
wkspa_has_mounted (){
    _wkspsa_filtered_ls "mounted"
    if [ "${#_WKSPSA_ARCHIVES_ID[@]}" -eq "0" ]; then
	return 1
    else
	return 0
    fi
}

# -------------------------------------------------------------------------
# wkspa
# -------------------------------------------------------------------------

wkspa() {
    if [ ! $_WKSPSA_SQFS_ENABLED ]; then
	log_error "SquashFS is not installed so workspace archiving is disabled"
	return 0
    fi

}



# -------------------------------------------------------------------------
#
# -------------------------------------------------------------------------

# Check the dependencies to set the status when sourcing
_wkspsa_set_env
