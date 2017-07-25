#-------------------------------------------------------------------------
# logging.sh
#
# Provides (very) basic logging.
#
# Readonly variables (pseudo-constants) for logging level:
#    LOGGING_ERROR, LOGGING_WARN, LOGGING_INFO, LOGGING_DEBUG.

# Environment variables used:
#
# - LOGGING_LEVEL_STDERR - The logging level for logging to stderr
# - LOGGING_LEVEL_FILE - The logging level for logging to a file. Only used if
#                        file logging is enabled.
# - LOGGING_LOG_FILE - The name of a file for log output. If not set then no
#                      file logging.
# -------------------------------------------------------------------------

# Read-only constants
readonly LOGGING_ERROR=1
readonly LOGGING_WARN=2
readonly LOGGING_INFO=3
readonly LOGGING_DEBUG=4

# Default to LOGGING_INFO
readonly LOGGING_LEVEL_DEFAULT=${LOGGING_INFO}

#-----------------------------------------
# Get the current logging level for stderr and file
#-----------------------------------------
_logging_current_level_stderr(){
    if [ -z ${LOGGING_LEVEL_STDERR+x} ]; then
	echo ${LOGGING_LEVEL_DEFAULT}
    fi
    echo ${LOGGING_LEVEL_STDERR}
}

_logging_current_level_file(){
    if [ -z ${LOGGING_LEVEL_FILE+x} ]; then
	echo ${LOGGING_LEVEL_DEFAULT}
    fi
    echo ${LOGGING_LEVEL_FILE}
}

#-----------------------------------------
# Check that it is ok to log for the given level
# Note: for FILE also check that LOGGING_LOG_FILE is set.
#-----------------------------------------
_logging_ok_to_log_stderr(){
    local testlevel=$1
    local loglevel=$(_logging_current_level_stderr)
    if (( testlevel <= loglevel )); then
	return 0
    fi
    return 1
}

_logging_ok_to_log_file(){
    if [ "$LOGGING_LOG_FILE" == "" ]; then
	return 1
    fi
    local testlevel=$1
    local loglevel=$(_logging_current_level_file)
    if (( testlevel <= loglevel )); then
	return 0
    fi
    return 1
}

#-----------------------------------------
# Logging to stderr changes the colour depending on the log level:
# error - red, warn - orange, info - nothing, debug - blue.
#-----------------------------------------
_logging_error_stderr(){
    if _logging_ok_to_log_stderr $LOGGING_ERROR ; then
	local message=$@
	local ccred=$(echo -e "\033[0;31m")
	local ccend=$(echo -e "\033[0m")
	echo "$ccred$message$ccend" 1>&2
    fi
}

_logging_warn_stderr(){
    if _logging_ok_to_log_stderr $LOGGING_WARN ; then
	local message=$@
	local ccred=$(echo -e "\033[0;33m")
	local ccend=$(echo -e "\033[0m")
	echo "$ccred$message$ccend" 1>&2
    fi
}

_logging_info_stderr(){
    if _logging_ok_to_log_stderr $LOGGING_INFO ; then
	local message=$@
	echo "$message" 1>&2
    fi
}

_logging_debug_stderr(){
    if _logging_ok_to_log_stderr $LOGGING_DEBUG ; then
	local message=$@
	local ccred=$(echo -e "\033[0;34m")
	local ccend=$(echo -e "\033[0m")
	echo "$ccred$message$ccend" 1>&2
    fi
}

#-----------------------------------------
# Pretty formatted timestamp
#-----------------------------------------
_logging_now(){
    echo $(date "+%x %X")
}

#-----------------------------------------
# Logging to a file
#-----------------------------------------

_logging_error_file(){
    if _logging_ok_to_log_file $LOGGING_ERROR ; then
	local message=$@
	local now=$(_logging_now)
	echo "ERROR: $now $message"
    fi
}

_logging_warn_file(){
    if _logging_ok_to_log_file $LOGGING_WARN ; then
	local message=$@
	local now=$(_logging_now)
	echo "WARN:  $now $message"
    fi
}

_logging_info_file(){
    if _logging_ok_to_log_file $LOGGING_INFO ; then
	local message=$@
	local now=$(_logging_now)
	echo "INFO:  $now $message"
    fi
}

_logging_debug_file(){
    if _logging_ok_to_log_file $LOGGING_DEBUG ; then
	local message=$@
	local now=$(_logging_now)
	echo "DEBUG: $now $message"
    fi
}

#-----------------------------------------
# Now the user callable functions
#-----------------------------------------

log_error(){
    _logging_error_file $@
    _logging_error_stderr $@
}

log_warn(){
    _logging_warn_file $@
    _logging_warn_stderr $@
}

log_info(){
    _logging_info_file $@
    _logging_info_stderr $@
}

log_debug(){
    _logging_debug_file $@
    _logging_debug_stderr $@
}

