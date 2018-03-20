#----------------------------------------------------------------------
# Test the squashfs module
#----------------------------------------------------------------------

#!/usr/bin/env bash

BASHD=$HOME/local/etc/bash.d
[ "$_MB_IMPORTED_modules_bootstrap" != "1" ] && source $BASHD/modules_bootstrap.sh
mbimport logging

if ! mbforce squashfs ; then
    log_error "Failed to load squashfs"
fi

#test_logging

