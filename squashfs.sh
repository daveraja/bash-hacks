#-------------------------------------------------------------------------
# squashfs.sh
#
# Some wrappers around squashfs and squashfuse.
#
# - Squashfs provides a compressed read-only filesystem. There are tools
#   to create and extract squashfs filesystems.
# - Squashfuse allows squashfs filesystems to be mounted in userland
#   using the FUSE infrastructure.
#
# The squash commands are exported as environment variables:
# - SQUASHFS_MAKE_CMD - make a squashfs filesystem
# - SQUASHFS_EXTRACT_CMD - extract a squashfs filesystem
# - SQUASHFS_MOUNT_CMD - fuser mount a squashfs filesystem
# - SQUASHFS_UMOUNT_CMD - umount a fuser mounted squashfs filesystem
#
# -------------------------------------------------------------------------
mbimport misc_functions
mbimport logging

#--------------------------------------------------------------------------
# Setup the appropriate executables
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
_squashfs_umount_cmd(){
    local fusermount=$(_squashfs_fusermount_cmd)
    if [ "$fusermount" = "" ]; then
	log_error "Could not find fusermount command"
	echo ""
	return 1
    fi
    echo "$fusermount -u"
}

export SQUASHFS_MAKE_CMD=$(_squashfs_make_cmd)
export SQUASHFS_EXTRACT_CMD=$(_squashfs_extract_cmd)
export SQUASHFS_MOUNT_CMD=$(_squashfs_mount_cmd)
export SQUASHFS_UMOUNT_CMD=$(_squashfs_umount_cmd)

#--------------------------------------------------------------------------
# Check that the external dependencies are satisfied. Return 0 on success
#--------------------------------------------------------------------------
_squashfs_external_dependencies_satisfied(){
    local error=0
    if [ "$SQUASHFS_MAKE_CMD" == "" ] || \
       [ "$SQUASHFS_EXTRACT_CMD" == "" ]; then
	log_error "SQUASHFS is not installed"
	error=1
    fi
    if [ "$SQUASHFS_MOUNT_CMD" == "" ] || \
       [ "$SQUASHFS_UMOUNT_CMD" == "" ]; then
	log_error "SQUASHFUSE is not installed"
	error=1
    fi
    return $error
}


# Check the dependencies and return this status
_squashfs_external_dependencies_satisfied

#--------------------------------------------------------------------------
#--------------------------------------------------------------------------
