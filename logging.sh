#-------------------------------------------------------------------------
# logging.sh
#
# Provides (very) basic logging. For more advanced logging try:
# - https://sites.google.com/a/forestent.com/projects/log4sh
# - or the logger command for a syslog environment.
#
# Logs to stderr and optionally a log file or the desktop notification
# system. To log a message call one of the functions log_error, log_warn,
# log_info, and log_debug.
#
# Whether the called function actually logs is dependant on the current log
# level for that output.
#
# Readonly variables (pseudo-constants) for logging level:
#    LOGGING_ERROR, LOGGING_WARN, LOGGING_INFO, LOGGING_DEBUG, LOGGING_NONE
#
# The logging level is set by changing the environment variables:
#
# - LOGGING_LEVEL_STDERR - The logging level for logging to stderr
# - LOGGING_LEVEL_FILE - The logging level for logging to a file (note: only
#                        used if LOGGING_LOG_FILE variable is set).
# - LOGGING_LEVEL_DESKTOP - The logging level for desktop notifications.
#
# - LOGGING_LOG_FILE - The name of a file for log output. If not set then no
#                      file logging.
#
# -------------------------------------------------------------------------
mbimport misc_functions

# Read-only constants
readonly LOGGING_ERROR=1
readonly LOGGING_WARN=2
readonly LOGGING_INFO=3
readonly LOGGING_DEBUG=4
readonly LOGGING_NONE=5

# Default to LOGGING_INFO
readonly LOGGING_LEVEL_DEFAULT=${LOGGING_INFO}
readonly LOGGING_LEVEL_DESKTOP_DEFAULT=${LOGGING_NONE}

#-----------------------------------------
# Returns the program to call for desktop notifications.
# Needs to be run only once at load time.
#-----------------------------------------
_logging_desktop_notify_exe(){
    if mf_is_remote_shell; then
	echo ""
    else
	echo $(mf_which notify-send)
    fi
}
LOGGING_DESKTOP_SEND=$(_logging_desktop_notify_exe)

#-----------------------------------------
# Get the current logging level for different source
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

_logging_current_level_desktop(){
    if [ -z ${LOGGING_LEVEL_DESKTOP+x} ]; then
	echo ${LOGGING_LEVEL_DESKTOP_DEFAULT}
    fi
    echo ${LOGGING_LEVEL_DESKTOP}
}

#-----------------------------------------
# Check that it is ok to log for the given level
# Note: for FILE also check that LOGGING_LOG_FILE is set.
#-----------------------------------------
_logging_ok_to_log_stderr(){
    local testlevel=$1
    local loglevel=$(_logging_current_level_stderr)
    if (( loglevel == LOGGING_NONE )); then
	return 1
    fi
    if (( testlevel <= loglevel )); then
	return 0
    fi
    return 1
}

_logging_ok_to_log_desktop(){
    local testlevel=$1
    local loglevel=$(_logging_current_level_desktop)
    if [ "${LOGGING_DESKTOP_SEND}" == "" ]; then
	return 1
    fi
    if (( loglevel == LOGGING_NONE )); then
	return 1
    fi
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
    if (( loglevel == LOGGING_NONE )); then
	return 1
    fi
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
# Logging to the desktop.
#-----------------------------------------
_logging_error_desktop(){
    if _logging_ok_to_log_desktop $LOGGING_ERROR ; then
	local message=$@
	$($LOGGING_DESKTOP_SEND -u critical "ERROR" "$message")
    fi
}

_logging_warn_desktop(){
    if _logging_ok_to_log_desktop $LOGGING_WARN ; then
	local message=$@
	$($LOGGING_DESKTOP_SEND -t 3000 "WARN" "$message")
    fi
}

_logging_info_desktop(){
    if _logging_ok_to_log_desktop $LOGGING_INFO ; then
	local message=$@
	$($LOGGING_DESKTOP_SEND -t 2000 "INFO" "$message")
    fi
}

_logging_debug_desktop(){
    if _logging_ok_to_log_desktop $LOGGING_DEBUG ; then
	local message=$@
	$($LOGGING_DESKTOP_SEND -t 1000 "DEBUG" "$message")
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
	echo "ERROR: $now $message" >> ${LOGGING_LOG_FILE}
    fi
}

_logging_warn_file(){
    if _logging_ok_to_log_file $LOGGING_WARN ; then
	local message=$@
	local now=$(_logging_now)
	echo "WARN:  $now $message"  >> ${LOGGING_LOG_FILE}
    fi
}

_logging_info_file(){
    if _logging_ok_to_log_file $LOGGING_INFO ; then
	local message=$@
	local now=$(_logging_now)
	echo "INFO:  $now $message" >> ${LOGGING_LOG_FILE}
    fi
}

_logging_debug_file(){
    if _logging_ok_to_log_file $LOGGING_DEBUG ; then
	local message=$@
	local now=$(_logging_now)
	echo "DEBUG: $now $message" >> ${LOGGING_LOG_FILE}
    fi
}

#-----------------------------------------
# Now the user callable functions
#-----------------------------------------

log_error(){
    _logging_error_file $@
    _logging_error_stderr $@
    _logging_error_desktop $@
}

log_warn(){
    _logging_warn_file $@
    _logging_warn_stderr $@
    _logging_warn_desktop $@
}

log_info(){
    _logging_info_file $@
    _logging_info_stderr $@
    _logging_info_desktop $@
}

log_debug(){
    _logging_debug_file $@
    _logging_debug_stderr $@
    _logging_debug_desktop $@
}

