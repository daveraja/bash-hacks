#----------------------------------------------------------------------
# virtualbox.sh
#
# Functions to simplify interaction with virtualbox. Basically some
# wrappers around the "VBoxManage" command-line. 
#
# It is easiest to work with a virtual machine's uuid rather than the
# name (since the uuid doesn't have spaces). Therefore for all the
# functions other than vbox_get_uuid() a VM is always referenced by
# the uuid.
# ----------------------------------------------------------------------

#----------------------------------------------------------------------
# vbox_get_uuid <vm-name>
#
# Returns the uuid corresponding to the VM name. This is probably the
# first thing to use. From then on you can work with the uuid.
#
# Must be called using the $(...) pattern. Returns "" on any error.
#----------------------------------------------------------------------

vbox_get_uuid () {
    local vmn="$1"
    if [ "$vmn" == "" ]; then
	echo ""
	return 1
    fi
    local match=$(vboxmanage list vms | grep -m 1 "$vmn")
    if [ "$match" == "" ]; then
	echo ""
	return 1
    fi
    local uuid=$(echo "$match" | sed -n 's/^[^{]*{\([^}]*\)}/\1/p')
    echo "$uuid"
    return 0   
}

#----------------------------------------------------------------------
# vbox_get_vmname <uuid>
#
# Returns the vm name corresponding to the VM uuid. Must be called using the
# $(...) pattern. Returns "" if there is any error.
#----------------------------------------------------------------------

vbox_get_vmname () {
    local uuid="$1"
    if [ "$uuid" == "" ]; then
	echo ""
	return 1
    fi
    local match=$(vboxmanage list vms | grep -m 1 "$uuid")
    if [ "$match" == "" ]; then
	echo ""
	return 1
    fi
    local vmname=$(echo "$match" | sed -n 's/^\"\([^\"]*\)\" [^{]*{[^}]*}/\1/p')
    echo "$vmname"
    return 0   
}

#----------------------------------------------------------------------
# vbox_is_vm <uuid>
#
# Returns 0 (true) if the uuid corresponds to a valid registered VM.
# returns 1 (false) otherwise
#----------------------------------------------------------------------
vbox_is_vm () {
   local uuid="$1"
    if [ "$uuid" == "" ]; then
	echo "$FUNCNAME: missing virtual machine: uuid"
	return 1
    fi
    local match=$(vboxmanage list vms | grep -m 1 "$uuid")
    if [ "$match" == "" ]; then
	return 1
    fi

    local matcheduuid=$(echo "$match" | sed -n 's/^[^{]*{\([^}]*\)}/\1/p')
    if [ "$uuid" == "$matcheduuid" ]; then
	return 0
    fi
    return 1
}

#----------------------------------------------------------------------
# vbox_is_running <uuid>
#
# Returns 0 if the named virtual machine is running. Returns 1 
# otherwise and if there is some error prints a warning.
#----------------------------------------------------------------------

vbox_is_running () {
    local uuid="$1"
    if ! vbox_is_vm "$uuid"; then
	echo "$FUNCNAME: invalid virtual machine: $uuid"
	return 1
    fi
    local running=$(vboxmanage list runningvms | grep -m 1 "$uuid")
    if [ "$running" == "" ]; then
	return 1
    fi
    return 0
}

#----------------------------------------------------------------------
# vbox_start_headless <uuid>
# vbox_start_gui <uuid>
#
# Starts the vm in different modes mode. Returns 0 on success otherwise 
# prints error and returns 1.
#----------------------------------------------------------------------
vbox_start_headless () {
   local uuid="$1"
   vbox_start "$uuid" "headless"
}
vbox_start_gui () {
   local uuid="$1"
   vbox_start "$uuid" "gui"
}

#----------------------------------------------------------------------
# vbox_start <uuid> [gui|sdl|headless]
#
# Starts the vm in headless mode. Returns 0 on success otherwise 
# prints error and returns 1.
#----------------------------------------------------------------------
vbox_start () {
   local uuid="$1"
   local type="$2"
   if [ "$type" == "" ]; then
       type="gui"
   fi
   if [ "$type" != "gui" ] && [ "$type" != "headless" ] &&
       [ "$type" != "sdl" ]; then
       echo "$FUNCNAME: invalid virtual machine start type: $type"
       return 1
   fi
   if ! vbox_is_vm "$uuid"; then
       echo "$FUNCNAME: invalid virtual machine: $uuid"
       return 1
   fi
   if vbox_is_running "$uuid"; then
       echo "$FUNCNAME: virtual machine already running: $uuid"
       return 1
   fi
   vboxmanage startvm "$uuid" --type "$type"
   return 0
}

#----------------------------------------------------------------------
# vbox_shutdown_savestate <uuid>
# vbox_shutdown_acpipowerdown <uuid>
#
# 1- Shutsdown a running VM by saving the state. On the next start the
#    VM will be resumed from the saved state.
# 2 - Shutdown a running vm by issuing a ACPI power button call. This is
#     the cleanest way to shutdown the VM.
# 
#----------------------------------------------------------------------
vbox_shutdown_savestate () {
   local uuid="$1"
   vbox_shutdown "$uuid" "savestate"
}
vbox_shutdown_acpipowerbutton () {
   local uuid="$1"
   vbox_shutdown "$uuid" "acpipowerbutton"
}

#----------------------------------------------------------------------
# vbox_shutdown <uuid> [acpipowerbutton|savestate]
#
# Different ways of shutting down a VM. Currently supported are
# ACPI and savestate.
#
# Returns 0 on success otherwise prints error and returns 1.
#----------------------------------------------------------------------
vbox_shutdown () {
   local uuid="$1"
   local type="$2"

   if [ "$type" != "acpipowerbutton" ] && [ "$type" != "savestate" ]; then
       echo "$FUNCNAME: invalid virtual machine shutdown type: $type"
       return 1
   fi
   if ! vbox_is_running "$uuid"; then
       echo "$FUNCNAME: virtual machine is not running: $uuid"
       return 1
   fi  
   vboxmanage controlvm "$uuid" "$type"
   return 0
}



