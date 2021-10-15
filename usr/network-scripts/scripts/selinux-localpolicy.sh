#!/bin/sh

SELINUX_LOCAL=$HOME/selinux
MODULE_NAME=local_policy

selinux_audit2allow ()
{
    # This generates a .te file (policy in text) as well as loadable
    # binary module .pp file (semodule -i).
    #
    # ausearch is used because not all log may appear in audit.log
    #
    cd $SELINUX_LOCAL
    ausearch -m avc | audit2allow -M $MODULE_NAME
}

selinux_compile_te ()
{
    # Compile .te policy text into .pp loadable binary module
    #
    cd $SELINUX_LOCAL
    checkmodule -M -m -o ${MODULE_NAME}.mod ${MODULE_NAME}.te
    semodule_package -o ${MODULE_NAME}.pp -m ${MODULE_NAME}.mod
    rm -f ${MODULE_NAME}.mod
}

selinux_load ()
{
    semodule -i ${MODULE_NAME}.pp
}

case $1 in
    *)
      selinux_audit2allow
      ;;
esac
