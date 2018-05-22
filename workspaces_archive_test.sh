#----------------------------------------------------------------------
# Test the archive module
#----------------------------------------------------------------------

#!/usr/bin/env bash

source /opt/squashfuse/setup.sh

BASHD=$HOME/local/etc/bash.d
[ "$_MB_IMPORTED_modules_bootstrap" != "1" ] && source $BASHD/modules_bootstrap.sh
mbforce logging
mbforce workspaces

if ! mbforce workspaces_archive ; then
    log_error "Failed to load workspaces_archive"
fi

#------------------------------------------------------------------
# Setup the test environment
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEST_DIR=$THIS_DIR/test
#export WORKSPACES_METADATA_DIR="$TEST_DIR/.workspaces"
#export WORKSPACES_ARCHIVE_BASE_DIR=$TEST_DIR/archive

_wksps_set_env
_wkspsa_set_env

# Create two test workspaces
WORKSPACES_DIR=$TEST_DIR/workspaces

WS1=$WORKSPACES_DIR/tw1
WS2=$WORKSPACES_DIR/tw2

setup_test_dir(){
    _wksps_init
    _wkspsa_init

    # Create two test workspaces
    export WORKSPACES_DIR=$TEST_DIR/workspaces

    WS1=$WORKSPACES_DIR/tw1
    WS2=$WORKSPACES_DIR/tw2
    mkdir -p $WS1
    mkdir -p $WS2
    log_info "Creating test workspace: $WS1"
    log_info "Creating test workspace: $WS2"

    touch $WS1/README1.txt
    touch $WS2/README2.txt
    log_info "Workspace 1" > $WS1/README1.txt
    log_info "Workspace 2" > $WS2/README2.txt

    _wksps_mk $WS1
    _wksps_mk $WS2
}

#------------------------------------------------------------------
# Archive the workspace

make_archive(){
    setup_test_dir

    WSID1=$(_wksps_get_ws_id $WS1)
    WSDIR1=$(_wksps_get_ws_from_link_id $WSID1)
    [ "$WSDIR1" != "$WS1" ] && log_error "Mis-matched link '$WSDIR1' and '$WS1'"

    WSID2=$(_wksps_get_ws_id $WS2)
    WSDIR2=$(_wksps_get_ws_from_link_id $WSID2)
    [ "$WSDIR2" != "$WS2" ] && log_error "Mis-matched link '$WSDIR2' and '$WS2'"
    _wkspsa_make $WSID1
    echo $WSID1
}

#WSID1=$(make_archive)

#WSID1=0384624312

#res=$(prompt_yesno "Mount the archived workspace $WSID1? (Y/n)" y)
res="n"
if [ "$res" == "y" ]; then
    _wkspsa_mount $WSID1
fi

#res=$(prompt_yesno "Unmount the archived workspace $WSID1? (Y/n)" y)

if [ "$res" == "y" ]; then
    _wkspsa_umount $WSID1
fi

#_wkspsa_filtered_ls inactive
#_wkspsa_ls

_wkspsa_mount_sel
#_wkspsa_unmount_sel


#WSID1=2040310031

#_wkspsa_umount $WSID1

#log_error "$WS1 has ID $WSID1"
#log_error "$WSID1 has id $WSDIR1"

#wkspsa_make





#test_logging

