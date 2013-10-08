bash-hacks
===========

Some bash hacks to make life easier. 

Basics - modules
----------------

Each script is viewed as a module. Bash itself doesn't really have the
notion of modules so we invent one with the modules_bootstrap.sh. A
module is simple a shell script ending in ".sh". The name of module is
the filename without the ending ".sh".

There are two basic function to import modules:

        mbimport <module_name> [module_arguments]
        mbforce <module_name> [module_arguments]

These functions provide wrappers around the the bash "source"
command. While calling "source" on a script is simple enough it does
have a couple of limitations which we try to address:

1. You need to know where the file is located, so you typically put
       all support scripts in the same directory as the calling
       script. To address this we use the wrapper import functions use
       the `MODULE_PATH` variable. This path will be searched to find
       the first filename that matches the module name. Note: the
       limitation is that it means that module names must be unique.

2. The "source" command doesn't provide a mechanism to know if a
       script has already been loaded. If you have a base script
       containing general utility functions that are used across many
       scripts (e.g., list processing functions). You will end up
       "sourcing" the same file multiple times. To deal with this the
       provided import functions set environment variables named
       `_MB_IMPORTED_<module_name>` which are then checked to see if the
       module has already been loaded.

See the comments at the top of the modules_bootstrap.sh script for
more details.
    
Many of the following bash-hacks modules expect the
modules_bootstrap.sh script to have been loaded.

The rest of this readme provides details of the different modules.

Workspaces
----------

The workspaces module provides functions to setup and control
workspaces. A workspace is simply a directory containing some special
files. Workspaces have their own setup and exit scripts as well
maintaining their own bash history.

Working within a workspace is implemented by running a sub-bash
shell. This ensures that workspaces doesn't polute each others
environment spaces. 

Note, that this whole sub-shell thing should be reasonably transparent
to the user and should feel like you are working in a normal
environment. Much of the smarts of this module try to maintain this
illusion, for example if you call "exit" it should do what you expect,
and not simply exit the workspace sub-shell. I'm still undecided if
this approach is too heavy handed, but so far seems to work reasonably
well.

Following are the environment variables and special files that are
used by this module.
 
* Special files/directories:
  * `.workspace` sub-directory is created in the directory that is a workspace. 
     This sub-directory contains:
     * `on_enter.sh` - file that is run on workspace startup
     * `on_exit.sh`   - file that is run on workspace exit
     * `bash_history` - use this file to maintain the bash history. 
     * `id.<NNNN>`    - randomly generated unique identify for workspace.
 * `~/.workspaces` - Contains symlinks to all registered workspaces allowing 
     for easy listing and switching betwen workspaces.
     
* Some environment variables that may be useful
  * WORKSPACE_DIR - A workspace HOME directory.
  * WORKSPACE_ID - A workspace identifier, from the workspace id file.

Main user callable command functions:
  * wksp <cmd> <args> - run "wksp help" for more information.
  * ws   - shortcut for "wksp chg" to switch between workspaces.
  * wsls - shortcut for "wksp ls". "ls" relative to WORKSPACE_DIR.
  * wscd - shortcut for "wksp cd". "cd" relative to WORKSPACE_DIR.
