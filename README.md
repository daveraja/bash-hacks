bash-hacks
===========

Some bash hacks to make life easier in bash. Firstly, defines a shell
script that implements a simple notion of *modules*. Then, provides
some standard modules.

Module boostrapping 
-------------------

Provides some bash *modules* containing various support
functions. Since, bash itself doesn't have a built-in notion of
modules a simple one with provided by *modules_bootstrap.sh*. A module
is simply a shell script ending in *.sh*. The name of module is the
filename without the ending *.sh*.

To usea module it needs to be loaded (imported). There are two basic
functions to import modules:

     mbimport <module_name> [module_arguments]
     mbforce <module_name> [module_arguments]

The first loads the module only if it hasn't been loaded previously,
while the second forces the module to be loaded even if it has
previously been loaded. Both these functions provide a wrapper around
the the bash `source` command. 

While calling `source` on a script is simple enough it does have a
couple of limitations which the the module commands try to address:

1. You need to know where the file is located. Typically support
   scripts are placed in the same directory as the calling script. To
   address this the wrapper import functions use the `MODULE_PATH`
   variable. The path defined by this variable will be searched to
   find the first filename that matches the module name. Note: of
   course the limitation of this is that that module names must be
   unique across all files in `MODULE_PATH`.

2. The `source` command doesn't provide a mechanism to know if a
   script has already been loaded. For example, if you have a base
   script containing general utility functions that are used across
   many scripts (e.g., list processing functions), you may end up
   "sourcing" the same file multiple times. To deal with this the
   import functions an set environment variable named
   `_MB_IMPORTED_<module_name>`. This variable is checked to see if
   the module has already been loaded and to act accordingly. For
   `mbforce` the file is reloaded regardless, while for `mbimport` the
   file will be loaded only if it hasn't previously been loaded.

3. On exporting. The ability to export variables and functions so that
   they can be inherited by sub-processes complicates things
   somewhat. You may or may not want to export variables or functions
   depending on the scenario. Currently, I don't have got a good way
   to handle this, although see the comments at the top of the
   *modules_bootstrap.sh* script for some discussion. One problem, is
   that some properties of a shell such as defining aliases and
   setting up tab completions cannot be inherited by sub-shells. The
   `mbforce` command is useful for these latter cases where you want
   to always reload the module.

There is also a support function for adding paths to the modules
search path:

     mbset_MODULE_PATH <path>	   

You can of course set the `MODULE_PATH` environment variable manually,
but the function tries to be a bit smarter and only adds paths that
are not already present. Note: that executing *modules_bootstrap.sh*
will automatically add the directory that *modules_bootstrap.sh* is in
to the `MODULE_PATH`.

Usage
-----

As an example of how to use these modules my `.bashrc` now looks something
like the following:

    # Load up the base modules
    BASH_DIR=$HOME/local/etc/bash.d
    [ "$_MB_IMPORTED_modules_bootstrap" != "1" ] && source $BASH_DIR/modules_bootstrap.sh

    # add my local (computer specific) modules to the MODULE_PATH    
    mbset_MODULE_PATH $HOME/.bash.d

    # Import various modules
    mbimport misc
    mbimport java
    mbimport local
    mbimport proxy

    # Aliases and completions are not inherited so force import every time.
    mbforce terminal
    mbforce workspaces


Modules
-------

The following defines some useful modules. The current list of
available modules are:

* prompts - provides simple prompts (currently only yes/no)
* workspaces - provides bash workspace functionality.
* workspaces_emacs - integrates emacs into a workspace.

Workspaces
----------

The workspaces module provides functions to setup and control
bash-based workspaces. A workspace is simply a directory containing
some special files. Workspaces have their own setup and exit scripts
as well maintaining their own bash history.

Working within a workspace is implemented by running a sub-bash
shell. This ensures that workspaces don't polute each others
environment spaces. 

Note, that this whole sub-shell thing should be reasonably transparent
to the user and should feel like you are working in a normal
environment. Much of the smarts of this module are about maintaining
this illusion. For example if you call `exit` from within a loaded
workspace you want it to act like it was called in a normal
shell. Hence, the workspace functions will actually end up calling
`exit` twice, once to exit the workspace and again to exit the base
shell. I'm still undecided if this approach is too heavy handed, but
so far it seems to work reasonably well.

Workspaces use a simple extension concept where other modules can
register hooks (ie. functions) that are run on entering and exiting
workspaces.  `workspaces_emacs` is such an extension that integrates
named emacs servers for each workspace. It registers an on_enter hook
that is run on entering a workspace and sets up the `EDITOR`
environment variable to use the wkspe_emacsclient function. It also
registers an on_exit hook that is run on exiting a workspace. This
hook is used to check if the shell exiting the workspace is the last
running instance of that workspace and if so will make sure the emacs
server for that workspace is shutdown.

Following are the special files that are used by this module.
 
* Special files/directories:
  * `.workspace` - this sub-directory is created in the directory that is a workspace. 
     This sub-directory contains:
     * `on_enter.sh`  - file that is run on workspace startup. Edit as necessary.
     * `on_exit.sh`   - file that is run on workspace exit. Edit as necessary.
     * `bash_history` - use this file to maintain the bash history. 
     * `id.<NNNN>`    - randomly generated unique identify for workspace.
     * `pids.tmp`     - a temporary file that tracks the open shells for a workspace.

     * `~/.workspaces` - Contains symlinks to all registered workspaces. 
                         This allows for the provision of functions to list
                         and switching betwen workspaces.
     
* Some environment variables that may be useful from the startup or
  exit scripts:
  * `WORKSPACE_DIR` - the workspace HOME directory.
  * `WORKSPACE_ID`  - a workspace identifier, from the workspace id file.

Main user callable command functions:
  * `wksp help` - full list and descriptions of the various options.
  * `wksp add` - configure a directory as a workspace.
  * `wksp sel` - change to a workspace by selecting from a numbered list.
  * `wksp load_if` - If the current directory is a workspace then load it. 
                     Useful for adding to .bash_profile to automate 
                     loading workspaces.
  * `wsls [file]` - shortcut for "wksp ls". "ls" relative to `WORKSPACE_DIR`.
  * `wscd [directory]` - shortcut for "wksp cd". "cd" relative to `WORKSPACE_DIR`.
